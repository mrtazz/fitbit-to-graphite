# fitbit-to-graphite

## Synopsis
Record sleep data from fitbit to graphite. That's it.

## Installation
You can get the script from rubygems:

    gem install fitbit-to-graphite


## Usage
```
% fitbit-to-graphite.rb --help
Usage: fitbit-to-graphite.rb [-hpnv]

Specific options:
    -h, --host=HOST                  The hostname or ip of the host graphite is running on
    -p, --port=PORT                  The port graphite is listening on
    -n, --namespace=NAMESPACE        The graphite metric path to store data in

Common options:
        --help                       Show this message
    -v, --version                    Show version
        --debug                      run in debug mode
        --jawbone                    send jawbone compatible data
```

## How to contribute
1. Fork the repo
2. Hack away
3. Push the branch up to GitHub
4. Send a pull request

