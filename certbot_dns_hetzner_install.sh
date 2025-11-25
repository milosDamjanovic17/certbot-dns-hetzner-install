#!/usr/bin/env bash

# First of all, check if snapd is installed
if ! command -v snap >/dev/null 2>&1; then
   echo "===> snapd is NOT installed"
   
   while true; do
      read -p "===> Do you want to install snapd? (y/n): " answer

      case $answer in
         y|Y)
            echo " ===> Installing snapd..."
            sudo apt update && sudo apt install -y snapd && sudo snap install core -y
            break
            ;;
         n|N)
            echo "===> snapd installation skipped. Exiting..."
            exit 1
            ;;
         *)
            echo "===> Invalid option. Enter 'y' or 'n' (or press Ctrl+C to exit)"
            ;;
      esac
   done
else
   echo "===> snapd is already installed"
fi

# installing certbot via snap + hetzner DNS plugin auch
echo "===> Installing Certbot and Hetzner DNS plugin....."

# error handling function
run_or_fail_check() {
   CMD="$1"
   DESC="$2"

   echo "-> $DESC"
   if ! eval "$CMD"; then
      echo "-> Error: Failed while: $DESC"
      echo "-> Aborting. Fix the error or try again..."
      exit 1
   fi
}

# snapd core, certbot and hetzner plugin install
run_or_fail_check "sudo snap install core" "Installing snap core"
run_or_fail_check "sudo snap install --classic certbot" "Installing Certbot"
run_or_fail_check "sudo snap set certbot trust-plugin-with-root=ok" "Setting Certbot to trust plugins"
run_or_fail_check "sudo snap install certbot-dns-hetzner-cloud"

# connecting the plugin
run_or_fail_check "sudo snap connect certbot:plugin certbot-dns-hetzner-cloud" "Connecting Certbot Hetzner plugin"

echo "===> Certbot + Hetzner DNS plugin successfully installed and configured. Proceeding with DNS "

# Check if certbot successfully loaded the plugin
echo "===> Verifying Certbot plugin installtion....."
PLUGIN_OUTPUT=$(certbot plugins 2>/dev/null)
if echo "$PLUGIN_OUTPUT" | grep -q "dns-hetzner-cloud"; then
    echo "Hetzner DNS plugin detected: dns-hetzner-cloud"
else
    echo "ERROR: Hetzner DNS plugin NOT found."
    echo "Output from certbot plugins:"
    echo "$PLUGIN_OUTPUT"
    echo "Something went wrong during plugin installation. Exiting."
    exit 1
fi

# Prompt user to enter DNS API token and create .ini file
echo
echo "===> Enter your Hetzner DNS Api Token (NO QUOTES):"
read -r HETZNER_TOKEN

# check that the token ain't empty
while [[ -z "$HETZNER_TOKEN" ]]; do
    echo "Token cannot be empty. Enter again:"
    read -r HETZNER_TOKEN
done

echo
echo "===> Do you want to store credentials in the default path(y|n):"
echo "/etc/letsencrypt/hetzner-cloud.ini ?"

# ask user for y/n with validation loop
while true; do
   read -p "(y|n) " yn
   case "$yn" in
      y|Y)
          INI_PATH="/etc/letsencrypt/hetzner-cloud.ini"
          break
          ;;
      n|N)
         # ask for custom path and VALIDATE, WICHTIG! Path must exist!
         while true; do
            read -p "===> Enter the FULL path where hetzner-cloud.ini should be stored(Make sure that path exists!): " custom_path

            if [[ -z "$custom_path" ]]; then
               echo "===> PATH cannot be empty. Try again....."
               continue
            fi
            # Validate that path exists
            dir=$(dirname "$custom_path")
            if [[ ! -d "$dir" ]]; then
               echo "===> Directory '$dir' does NOT exist. Enter a valid path."
               continue
            fi

            INI_PATH="$custom_path"
            break
         done
         break
         ;;
      *)
         echo "===> Invalid option. Enter 'y' or 'n' (or Ctrl+C to exit)."
   esac
done

echo
echo "===> Writing API token to: $INI_PATH"

# write the .ini file
if ! echo "dns_hetzner_cloud_api_token = $HETZNER_TOKEN" | sudo tee "$INI_PATH" >/dev/null; then
    echo "===> ERROR: Failed to write the .ini file. Fix permissions and try again."
    exit 1
fi

if ! sudo chmod 600 "$INI_PATH"; then
    echo "ERROR: Failed to set permissions on $INI_PATH"
    exit 1
fi

echo "Credentials stored successfully and permissions locked down."

# Certificate request logic
while true; do
   read -p "Enter the domain for the certificate (e.g., '*.mydomain.com' for wildcard or 'example.mydomain.com' for single domain): " ENTERED_DOMAIN
   
   # sanity check
   if [[ -z "$ENTERED_DOMAIN" ]]; then
      echo "Domain can't be empty. Try again...."
      continue
   fi

   echo
   echo "===> You entered: $ENTERED_DOMAIN"
   read -p "Is the domain correct? y/n: " CONFIRM_DOMAIN

   case "$CONFIRM_DOMAIN" in
      y|Y)
         break
         ;;
      n|N)
         echo "Type the domain name again."
         ;;
      *)
         echo "Invalid option. Enter 'y' or 'n' (or Ctrl+C to exit)."
   esac
done

# Request the Certificate to run based on the INI_PATH
echo
echo "===> Requesting certificate for $ENTERED_DOMAIN ..."

if [[ "$INI_PATH" == "/etc/letsencrypt/hetzner-cloud.ini" ]]; then
    sudo certbot certonly --agree-tos --authenticator dns-hetzner-cloud -d "$ENTERED_DOMAIN"
else
    sudo certbot certonly --agree-tos --dns-hetzner-cloud-credentials "$INI_PATH" -d "$ENTERED_DOMAIN"
fi

# sanity check if certbot command succeeded
if [[ $? -eq 0 ]]; then
    echo "Certificate successfully requested for $ENTERED_DOMAIN"
else
    echo "ERROR: Certificate request failed for $ENTERED_DOMAIN"
    exit 1
fi


# check if certificate exists and run dry run renewal
# *****DUEO TO CHANGE since there are two ways to implement this, either by checking the absolute path or via certbot certificates command
# pattern for checking the absolute path
CERT_PATH="/etc/letsencrypt/live/$ENTERED_DOMAIN/fullchain.pem"

echo
echo "Verifying certificate existence and readability..."

if [[ -f "$CERT_PATH" && -r "$CERT_PATH" ]]; then
    echo "===> Certificate file exists and is readable!: $CERT_PATH"
else
    echo "===> ERROR: Certificate file NOT found or not readable: $CERT_PATH"
    echo "===> Something went wrong with the certificate issuance. Exiting."
    exit 1
fi

# run the dry run renewal test
echo
echo "===> Running Certbot dry-run renewal to verify renewal process..."

if sudo certbot renew --dry-run; then
    echo "===> Dry-run renewal successful. Certificate setup complete.."
else
    echo "===> ERROR: Dry-run renewal failed. Check Certbot configuration and plugin."
    exit 1
fi


# TODO - #1 Add a logic for checking if certbot exists but its executed from APT, if yees, remove the APT version and merge it to SNAPD
# #2 Add a cleanup where it shows the user which certificates exist in certbot and opt him to remove the certificate