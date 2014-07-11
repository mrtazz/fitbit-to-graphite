#!/usr/bin/env ruby

#
# simple script to import your sleep data from Fitbit into Graphite
#

require 'date'
require 'yaml'

require 'choice'
require 'fitgem'
require 'tzinfo'

PROGRAM_VERSION = "0.2.1"
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

  option :date do
    short '-d'
    long '--date=DATE'
    desc 'the date to get data for in the format YYYY-MM-DD'
  end
  
  option :period do
    short '-p'
    long '--period=PERIOD'
    desc 'the date range period, one of 1d, 7d, 30d, 1w, 1m'
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

  option :weight do
	short '-w'
    long '--weight'
    desc 'retrieve weight instead of sleep (default is sleep)'
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

def get_sleep_data(client)

  user_info = client.user_info
  user_timezone_name = user_info['user']['timezone']
  user_timezone = offset = TZInfo::Timezone.get(user_timezone_name).current_period.utc_total_offset / (60*60)
  if Choice[:date]
    today = date = Date.strptime(Choice[:date],"%Y-%m-%d")
  else
    today = Date.today
  end
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
  if sleep_data.length == 0
    puts "No sleep data recorded for #{today}"
    return
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
  return msg
end

def get_weight_data(client)
  user_info = client.user_info
  user_timezone_name = user_info['user']['timezone']
  user_timezone = offset = TZInfo::Timezone.get(user_timezone_name).current_period.utc_total_offset / (60*60)
  if Choice[:date]
    today = date = Date.strptime(Choice[:date],"%Y-%m-%d")
  else
    today = Date.today
  end
  
  if Choice[:period]
	period = Choice[:period]
  else
    period = '1d'
  end
  
  #all_sleep_data = client.sleep_on_date(today)['sleep']
  all_weight_data = client.body_weight(base_date: today, period: period)

  if all_weight_data.nil?
    puts "API rate limit potentially exceeded."
    return
  end
  
  all_weight_data = all_weight_data['weight']
  
  if all_weight_data.length == 0
    puts "No weight data recorded for #{today}"
    return
  end
  
  msg = ""
  all_weight_data.each do |entry|
    createdate = DateTime.strptime("#{entry['date']}T#{entry['time']}#{user_timezone}",'%Y-%m-%dT%H:%M:%S%z').to_time.to_i
    msg << "#{Choice[:namespace]}.weight #{entry['weight']} #{createdate}\n"
  end
	
  return msg
end

def send_to_graphite(msg)
  socket = TCPSocket.open(Choice[:host], Choice[:port])
  socket.write(msg)
end

def print_data(msg)
  puts msg
end


# main
client = client_setup
msg = ""
if Choice[:weight]
	msg = get_weight_data(client)
  else
	msg = get_sleep_data(client)
  end
if Choice[:debug] 
  print_data(msg)
else
  send_to_graphite(msg)
end
