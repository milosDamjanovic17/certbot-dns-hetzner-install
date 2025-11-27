Certbot + Hetzner DNS Automation Script

The script automates the complete setup of Certbot (Snap version) with the Hetzner DNS plugin that targets new DNS Challenge Endpoint, handles conflicts with the APT version of Certbot, configures credentials, orders the certificate, and verifies renewal.

Script must be executed with sudo rights(either as sudo or root),
It is recommended if on the first run certificate order fails, to extended the default wait time limit(30s), because sometimes depending on bandwidth/server it takes more than 30s for DNS Challenges to complete.
If DNS Challenge doesn't complete before the time defined, certbot will register a fail certificate order and entire certificate renewal/order process will fail.
Recommended is either 60s or 75s.
You can update the default wait time by appending  dns-hetzner-cloud-propagation-seconds = 60 in /etc/letsencrypt/cli.ini

dns-hetzner-cloud-propagation-seconds = 60

What the Script Does
1. Detects APT-based Certbot

    Checks if the APT version of Certbot is installed.

    If found, user is prompted to remove it (y/n).

    Only removes the package, not configs, so existing certificates remain intact.

2. Installs Snap + Certbot

    Ensures snapd is installed (prompts user if missing).

    Installs:

    core

    certbot (Snap version)

    certbot-dns-hetzner-cloud plugin

    Enables trust-plugin-with-root, which is required for DNS plugins.
    This is safe: Snap plugins are verified packages and maintained upstream.

3. Validates Plugin Installation

    Runs certbot plugins to confirm dns-hetzner-cloud exists.

    If plugin is missing, the script stops to avoid a broken installation.

4. Handles the Hetzner API Token

    Prompts the user for their Hetzner DNS API token. User must enter the credentials without quotes

    Asks whether to use the default credentials file:

    /etc/letsencrypt/hetzner-cloud.ini or a custom path for example /var/log/supesecret.ini

    Validates that the chosen file exists before writing

    Sets strict permissions (chmod 600) so only root can read it

5. Certificate Request

    User inputs domain (wildcard or full domain).

    Script confirms domain with a y/n sanity check.

    Runs the correct certbot command depending on credentials file:

    Default ini:
    certbot certonly --agree-tos --authenticator dns-hetzner-cloud -d ...

    Custom ini:
    certbot certonly --agree-tos --dns-hetzner-cloud-credentials <path> --authenticator dns-hetzner-cloud -d ...

6. Post-Issue Verification

    Confirms the issued certificate files exist and are readable.

    Runs:

    certbot renew --dry-run

    to ensure renewal will work with no unexpected errors later.

Notes

    The script is fully interactive and validates every important input.

    Errors stop the script immediately to prevent partial or broken setups.