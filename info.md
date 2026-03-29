# CodeTunner v1.0.0

## SSH Stability Update

- Fixed "No common key algorithm" error by updating `russh` configuration.
- Added support for legacy algorithms (diffie-hellman-group14-sha1, ssh-rsa) for broader compatibility.
- Implemented robust keep-alive and timeout settings.
