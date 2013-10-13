#!/usr/bin/env ruby

#
# simple script to import your sleep data from Fitbit into Graphite
#

require 'date'
require 'yaml'

require 'choice'
require 'fitgem'

PROGRAM_VERSION = "0.1.1"
SLEEP_STATE_TYPES = ['deep', 'light', 'awake']
# this is just to be compatible with jawbone data
JAWBONE_SLEEP_STATES = { 'awake' => 1, 'light' => 2, 'deep' => 3 }

Choice.options do
  header ''
  header 'Specific options:'

  option :host do
    short '-h'
    long '--host=HOST'
    desc 'The hostname or ip of the host graphite is running on'
    default '127.0.0.1'
  end

  option :port do
    short '-p'
    long '--port=PORT'
    desc 'The port graphite is listening on'
    cast Integer
    default 2003
  end

  option :namespace do
    short '-n'
    long '--namespace=NAMESPACE'
    desc 'The graphite metric path to store data in'
  end

  separator ''
  separator 'Common options: '

  option :help do
    long '--help'
    desc 'Show this message'
  end

  option :version do
    short '-v'
    long '--version'
    desc 'Show version'
    action do
      puts "#{$0} Fitbit sleep data importer v#{PROGRAM_VERSION}"
      exit
    end
  end

  option :debug do
    long '--debug'
    desc 'run in debug mode'
  end

  option :jawbone do
    long '--jawbone'
    desc 'send jawbone compatible data'
  end
end

def client_setup
  # Load the existing yml config
  config = begin
    Fitgem::Client.symbolize_keys(YAML.load(File.open(File.join(ENV['HOME'], ".fitgem.yml"))))
  rescue ArgumentError => e
    puts "Could not parse YAML: #{e.message}"
    exit
  end

  client = Fitgem::Client.new(config[:oauth])

  # With the token and secret, we will try to use them
  # to reconstitute a usable Fitgem::Client
  if config[:oauth][:token] && config[:oauth][:secret]
    begin
      access_token = client.reconnect(config[:oauth][:token], config[:oauth][:secret])
    rescue Exception => e
      puts "Error: Could not reconnect Fitgem::Client due to invalid keys in .fitgem.yml"
      exit
    end
  # Without the secret and token, initialize the Fitgem::Client
  # and send the user to login and get a verifier token
  else
    request_token = client.request_token
    token = request_token.token
    secret = request_token.secret

    puts "Go to http://www.fitbit.com/oauth/authorize?oauth_token=#{token} and then enter the verifier code below"
    verifier = gets.chomp

    begin
      access_token = client.authorize(token, secret, { :oauth_verifier => verifier })
    rescue Exception => e
      puts "Error: Could not authorize Fitgem::Client with supplied oauth verifier"
      exit
    end

    user_id = client.user_info['user']['encodedId']

    config[:oauth].merge!(:token => access_token.token, :secret => access_token.secret, :user_id => user_id)

    # Write the whole oauth token set back to the config file
    File.open(File.join(ENV['HOME'], ".fitgem.yml"), "w") {|f| f.write(config.to_yaml) }
  end

  return client
end

def extract_data(client, &block)
  if block.nil?
    puts "No block given."
    return
  end
  user_info = client.user_info
  user_timezone = user_info['user']['timezone']
  today = Date.today
  all_sleep_data = client.sleep_on_date(today)['sleep']
  if all_sleep_data.nil?
    puts "API rate limit potentially exceeded."
    return
  end
  sleep_data = []
  sleep_summary = nil
  all_sleep_data.each do |potential_log|
    if potential_log['isMainSleep']
      sleep_data = potential_log['minuteData']
      sleep_summary = potential_log
    end
  end
  createdate = DateTime.strptime("#{sleep_summary['startTime']}#{user_timezone}",'%Y-%m-%dT%H:%M:%S.%L%z').to_time.to_i
  msg = ""
  msg << "#{Choice[:namespace]}.summary.awakenings #{sleep_summary['awakeningsCount']} #{createdate}\n"
  msg << "#{Choice[:namespace]}.summary.quality #{sleep_summary['efficiency']} #{createdate}\n"
  msg << "#{Choice[:namespace]}.summary.deep_minutes #{sleep_summary['minutesAsleep']} #{createdate}\n"
  msg << "#{Choice[:namespace]}.summary.light_minutes #{sleep_summary['minutesAwake']} #{createdate}\n"
  sleep_data.each do |data|
    d =  DateTime.strptime("#{today.year}-#{today.month}-#{today.day}T#{data['dateTime']}#{user_timezone}",'%Y-%m-%dT%H:%M:%S%z')
    state_name = SLEEP_STATE_TYPES[ data['value'].to_i - 1 ]
    value = Choice[:jawbone] == true ? JAWBONE_SLEEP_STATES[state_name] : data['value']
    msg << "#{Choice[:namespace]}.details.#{state_name} #{value} #{d.to_time.to_i}\n"
  end
  yield msg
end

def send_to_graphite(client)
  extract_data(client) do |msg|
    socket = TCPSocket.open(Choice[:host], Choice[:port])
    socket.write(msg)
  end
end

def print_sleep_data(client)
  extract_data(client) {|msg| puts msg}
end


# main
client = client_setup
if Choice[:debug]
  print_sleep_data(client)
else
  send_to_graphite(client)
end
