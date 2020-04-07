# zafp

Z shell plugin for accessing the AWS Federation Proxy (AFP).
Inspired by [afpre](https://github.com/leflamm/afpre/)
and by [afp-cli](https://github.com/Scout24/afp-cli).


## Installation and usage

Make sure you have `curl` and `jq` installed.
```zsh
curl --version
jq --version
```

If you are on a Mac, make sure that GNU `date` is installed:
```zsh
gdate --version
# The output should look like "date (GNU coreutils) 8.32".
# If gdate is not installed, you have to install coreutils:
brew install coreutils
```

Add the following line to your `~/.zshrc`:
```zsh
antigen bundle https://gitlab.build-unite.unite.eu/christoph.gietl/zafp.git
```

Create a `~/.zafp.zsh` based on `.zafp.zsh.template`:
```zsh
cp .zafp.zsh.template ~/.zafp.zsh
# Use your favourite editor to customise ~/.zafp.zsh.
```

Check if `zafp` and `unzafp` work as intended:
```zsh
# Start `zafp` using the defaults set in `~/.zafp.zsh`:
zafp
# Try a few AWS commands:
aws s3 ls
# Stop `zafp`:
unzafp
# Start `zafp` using a different account:
zafp analytics-stage01
# Stop `zafp`:
unzafp
# Start `zafp` using a different role:
zafp analytics-stage01 readonly
# Stop `zafp`:
unzafp
```
