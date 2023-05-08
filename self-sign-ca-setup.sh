#!/bin/bash
######################################################################################################################
# Create a self signing root CA
# David Harrop
# May 2023
######################################################################################################################

# Some useful OpenSSL testing commands:
# Verify new cert: openssl x509 -noout -text -in /path/to/script/cert-name.cert.pem
# Verify CA trust chain: openssl verify -CAfile $CA_ROOT_DIR/certs/ca.cert.pem $CA_ROOT_DIR/intermediate/certs/intermediate.cert.pem
# Verify certificate trust chain: openssl verify -CAfile $CA_ROOT_DIR/certs/ca.cert.pem -untrusted $CA_INT_DIR/certs/intermediate.cert.pem $CA_INT_DIR/certs/$CERT_NAME_SRV.cert.pem
# Verify CRL: openssl crl -in $CA_INT_DIR/crl/intermediate.crl.pem -noout -text
# Verify OCSP certificate: openssl x509 -noout -text -in $CA_ROOT_DIR/intermediate/certs/intermediate.ocsp.cert.pem
# Manually run the OCSP responder: openssl ocsp -port 2560 -text -index $CA_ROOT_DIR/intermediate/index.txt -CA intermediate/certs/ca-chain.cert.pem -rkey intermediate/private/intermediate.ocsp.key.pem -rsigner intermediate/certs/intermediate.ocsp.cert.pem -nrequest 1
# Manually query the OCSP responder: openssl ocsp -CAfile intermediate/certs/ca-chain.cert.pem -url http://127.0.0.1:2560 -resp_text -issuer intermediate/certs/intermediate.cert.pem -cert intermediate/certs/${REVOKE_OCSP}

# Prepare text output colours
GREY='\033[0;37m'
DGREY='\033[0;90m'
GREYB='\033[1;37m'
LRED='\033[0;91m'
LGREEN='\033[0;92m'
LYELLOW='\033[0;93m'
NC='\033[0m' #No Colour

# Initialise variables
ALGORITHM="RSA"						# RSA or EC (EC commands yet to be implemented)
CA_ROOT_DAYS="9215"					# Root CA lifetime
CA_INT_DAYS="7300"					# Intermediate CA lifetime
CA_PW="1111"						# Password to secure root & intermediate CA keys/certs
CERT_DAYS="3650"					# Number of days until new elf signed certificates will expire
CERT_PW="false"						# true/false (whether to encrypt user and server certs with an -aes256 password)
CERT_COUNTRY="AU"					# 2 country character code only, must not be blank
CERT_STATE="Victoria"				# must not be blank
CERT_LOCALITY="Melbourne"			# must not be blank
CERT_ORG="Itiligent"				# must not be blank
CERT_OU="I.T."						# must not be blank
CERT_EMAIL="admin@domain.com"		# Email to include inside certificates

# Set the various file paths
USER_HOME_DIR=$(eval echo ~${SUDO_USER})
CA_ROOT_DIR=$USER_HOME_DIR/ca
CA_INT_DIR=$CA_ROOT_DIR/intermediate
#LOG_LOCATION=$CA_ROOT_DIR/ca_setup.log
LOG_LOCATION=/dev/null 2>&1


# Begin interactive menu ##########################################################################################

# Script branding header
clear
echo -e "

	${GREYB}Itiligent Self Signed CA Setup & Operation.
				${LGREEN}Powered by OpenSSL


	${GREY}Script defaults:${DGREY}
	${DGREY}Encryption method\t= ${ALGORITHM}
	${DGREY}Root CA days\t\t= ${CA_ROOT_DAYS}
	Intermediate CA days\t= ${CA_INT_DAYS}
	CA key & cert password\t= ${CA_PW}
	New cert days\t\t= ${CERT_DAYS}
	New cert has password\t= ${CERT_PW}
	Cert country\t\t= ${CERT_COUNTRY}
	Cert state\t\t= ${CERT_STATE}
	Cert locality\t\t= ${CERT_LOCALITY}
	Cert ORG\t\t= ${CERT_ORG}
	Cert OU\t\t\t= ${CERT_OU}
	Cert Email\t\t= ${CERT_EMAIL}${GREY}


	${LGREEN}Choose self signed certificate authority actions below...

	Initial one-time Setup:${GREY}
	1) Create a new self signing certificate authority (Root CA & Intermediate CA)
	2) Setup/update a certificate revocation list (CRL)
	3) Setup/update online certificate status protocol (OCSP)

	${LGREEN}Ongoing certificate operations:${GREY}
	4) Generate a new SERVER certificate
	5) Generate a new USER certificate
	6) Revoke a certificate with CRL
	7) Revoke a certificate via OCSP
	8) Exit
	" > /tmp/menufile


while [[ 1 ]]
do
cat /tmp/menufile
	read -p "	Enter selection: " MENU
	case $MENU in

1)	# Set up new Root CA
	clear
	echo
	# Check if there is already a CA base present, and only create a new CA root structure if there are no root CA files in existence
	cd $USER_HOME_DIR
	if [ "$( find . -maxdepth 4 \( -name '*ca.key.pem' -o -name '*ca.cert.pem' \) )" != "" ]; then
	echo
	echo -e "${LRED}Existing CA configuration detected, please review CA status before continuing.${GREY}" 1>&2
	echo
	exit 1
	fi

	# Create the CA Root directory structure
	echo -e "${GREY}No root CA found, creating new root CA directory structure...${GREY}"
	mkdir -p $CA_ROOT_DIR
	cd $CA_ROOT_DIR
	mkdir -p $CA_ROOT_DIR certs crl newcerts private
	chmod 700 private
	mkdir -p $CA_INT_DIR
	cd $CA_INT_DIR
	mkdir -p $CA_INT_DIR certs crl csr newcerts private
	chmod 700 private
	if [ $? -ne 0 ]; then
	echo -e "${RED}Failed. See ${LOG_LOCATION}${GREY}" 1>&2
	exit 1
	else
	echo -e "${LGREEN}OK${GREY}"
	echo
	fi

	# Setup Root CA default policy
	cd $CA_ROOT_DIR
	touch index.txt
	echo 1000 > serial
	echo -e "${GREYB}Configuring root CA infrastructure default parameters..."
cat <<EOF | tee $CA_ROOT_DIR/openssl.cnf &>> ${LOG_LOCATION}
[ ca ]
default_ca = CA_default

[ CA_default ]
# Directory and file locations.
dir               = $CA_ROOT_DIR
certs             = $CA_ROOT_DIR/certs
crl_dir           = $CA_ROOT_DIR/crl
new_certs_dir     = $CA_ROOT_DIR/newcerts
database          = $CA_ROOT_DIR/index.txt
serial            = $CA_ROOT_DIR/serial
RANDFILE          = $CA_ROOT_DIR/private/.rand

# The root key and root certificate.
private_key       = $CA_ROOT_DIR/private/ca.key.pem
certificate       = $CA_ROOT_DIR/certs/ca.cert.pem

# For certificate revocation lists.
crlnumber         = $CA_ROOT_DIR/crlnumber
crl               = $CA_ROOT_DIR/crl/ca.crl.pem
crl_extensions    = crl_ext
crl_extensions    = crl_ext
default_crl_days  = 30

# Message Digest
default_md        = sha256

name_opt          = ca_default
cert_opt          = ca_default
default_days      = $CERT_DAYS
preserve          = no
policy            = policy_strict

[ policy_strict ]
# The root CA should only sign intermediate certificates that match.
countryName             = match
stateOrProvinceName     = match
organizationName        = match
organizationalUnitName  = optional
commonName              = supplied
emailAddress            = optional

[ policy_loose ]
# Allow the intermediate CA to sign a more diverse range of certificates.
countryName             = optional
stateOrProvinceName     = optional
localityName            = optional
organizationName        = optional
organizationalUnitName  = optional
commonName              = supplied
emailAddress            = optional

[ req ]
default_bits        = 2048
distinguished_name  = req_distinguished_name
string_mask         = utf8only
default_md          = sha256
x509_extensions     = v3_ca

[ req_distinguished_name ]
countryName                     = Country Name (2 letter code)
stateOrProvinceName             = State or Province Name
localityName                    = Locality Name
0.organizationName              = Organization Name
organizationalUnitName          = Organizational Unit Name
commonName                      = Common Name
emailAddress                    = Email Address

# Optionally, specify some defaults.
countryName_default             = $CERT_COUNTRY
stateOrProvinceName_default     = $CERT_STATE
localityName_default            = $CERT_LOCALITY
0.organizationName_default      = $CERT_ORG
organizationalUnitName_default  = $CERT_OU
emailAddress_default            = $CERT_EMAIL

[ v3_ca ]
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid:always,issuer
basicConstraints = critical, CA:true
keyUsage = critical, digitalSignature, cRLSign, keyCertSign

[ v3_intermediate_ca ]
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid:always,issuer
basicConstraints = critical, CA:true, pathlen:0
keyUsage = critical, digitalSignature, cRLSign, keyCertSign

[ usr_cert ]
basicConstraints = CA:FALSE
nsCertType = client, email
nsComment = "${CERT_ORG} User Certificate"
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid,issuer
keyUsage = critical, nonRepudiation, digitalSignature, keyEncipherment, keyAgreement
extendedKeyUsage = clientAuth, emailProtection, codeSigning, msCodeInd, msCodeCom, msEFS

[ server_cert ]
basicConstraints = CA:FALSE
nsCertType = server
nsComment = "${CERT_ORG} Server Certificate"
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid,issuer:always
keyUsage = critical, digitalSignature, keyEncipherment, dataEncipherment, keyAgreement
extendedKeyUsage = serverAuth, codeSigning, msCodeInd, msCodeCom, msEFS, timeStamping

[ crl_ext ]
authorityKeyIdentifier=keyid:always

[ ocsp ]
basicConstraints = CA:FALSE
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid,issuer
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, OCSPSigning
EOF
	if [ $? -ne 0 ]; then
	echo -e "${RED}Failed. See ${LOG_LOCATION}${GREY}" 1>&2
	exit 1
	else
	echo -e "${LGREEN}OK${GREY}"
	echo
	fi

	# Setup Intermediate CA default policy
	cd $CA_INT_DIR
	touch index.txt
	echo 1000 > serial
	echo 1000 > crlnumber
	echo -e "${GREYB}Configuring intermediate CA infrastructure default parameters..."
cat <<EOF | tee $CA_INT_DIR/openssl.cnf &>> ${LOG_LOCATION}
[ ca ]
default_ca = CA_default

[ CA_default ]
# Directory and file locations.
dir               = $CA_INT_DIR
certs             = $CA_INT_DIR/certs
crl_dir           = $CA_INT_DIR/crl
new_certs_dir     = $CA_INT_DIR/newcerts
database          = $CA_INT_DIR/index.txt
serial            = $CA_INT_DIR/serial
RANDFILE          = $CA_INT_DIR/private/.rand

# The root key and root certificate.
private_key       = $CA_INT_DIR/private/intermediate.key.pem
certificate       = $CA_INT_DIR/certs/intermediate.cert.pem

# For certificate revocation lists.
crlnumber         = $CA_INT_DIR/crlnumber
crl               = $CA_INT_DIR/crl/intermediate.crl.pem
crl_extensions    = crl_ext
default_crl_days  = 30

# Message Digest
default_md        = sha256

name_opt          = ca_default
cert_opt          = ca_default
default_days      = 375
preserve          = no
policy            = policy_loose

[ policy_strict ]
# The root CA should only sign intermediate certificates that match.
countryName             = match
stateOrProvinceName     = match
organizationName        = match
organizationalUnitName  = optional
commonName              = supplied
emailAddress            = optional

[ policy_loose ]
# Allow the intermediate CA to sign a more diverse range of certificates.
countryName             = optional
stateOrProvinceName     = optional
localityName            = optional
organizationName        = optional
organizationalUnitName  = optional
commonName              = supplied
emailAddress            = optional

[ req ]
default_bits        = 2048
distinguished_name  = req_distinguished_name
string_mask         = utf8only
default_md          = sha256
x509_extensions     = v3_ca

[ req_distinguished_name ]
countryName                     = Country Name (2 letter code)
stateOrProvinceName             = State or Province Name
localityName                    = Locality Name
0.organizationName              = Organization Name
organizationalUnitName          = Organizational Unit Name
commonName                      = Common Name
emailAddress                    = Email Address

# Optionally, specify some defaults.
# insert_common_name_below
countryName_default             = $CERT_COUNTRY
stateOrProvinceName_default     = $CERT_STATE
localityName_default            = $CERT_LOCALITY
0.organizationName_default      = $CERT_ORG
organizationalUnitName_default  = $CERT_OU
emailAddress_default            = $CERT_EMAIL

[ v3_ca ]
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid:always,issuer
basicConstraints = critical, CA:true
keyUsage = critical, digitalSignature, cRLSign, keyCertSign

[ v3_intermediate_ca ]
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid:always,issuer
basicConstraints = critical, CA:true, pathlen:0
keyUsage = critical, digitalSignature, cRLSign, keyCertSign

[ usr_cert ]
basicConstraints = CA:FALSE
nsCertType = client, email
nsComment = "${CERT_ORG} User Certificate"
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid,issuer
keyUsage = critical, nonRepudiation, digitalSignature, keyEncipherment, keyAgreement
extendedKeyUsage = clientAuth, emailProtection, codeSigning, msCodeInd, msCodeCom, msEFS

[ server_cert ]
# insert_int_srv_revocation_options_below
basicConstraints = CA:FALSE
nsCertType = server
nsComment = "${CERT_ORG} Server Certificate"
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid,issuer:always
keyUsage = critical, digitalSignature, keyEncipherment, dataEncipherment, keyAgreement
extendedKeyUsage = serverAuth, codeSigning, msCodeInd, msCodeCom, msEFS, timeStamping
subjectAltName      = @alt_names
[alt_names]
# insert_int_srv_dns_name_below

[ crl_ext ]
authorityKeyIdentifier=keyid:always

[ ocsp ]
basicConstraints = CA:FALSE
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid,issuer
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, OCSPSigning
EOF
	if [ $? -ne 0 ]; then
	echo -e "${RED}Failed. See ${LOG_LOCATION}${GREY}" 1>&2
	exit 1
	else
	echo -e "${LGREEN}OK${GREY}"
	echo
	fi


# RSA specific actions ############################################################################################

	# Generate RSA root key
if [[ "${ALGORITHM}" == "RSA" ]]; then
	cd $CA_ROOT_DIR
	echo -e "${GREYB}Generating root key...${GREY}"
	openssl genrsa -aes256 -passout pass:$CA_PW -out private/ca.key.pem 4096
	chmod 400 private/ca.key.pem
	if [ $? -ne 0 ]; then
	echo -e "${RED}Failed. See ${LOG_LOCATION}${GREY}" 1>&2
	exit 1
	else
	echo -e "${LGREEN}OK${GREY}"
	echo
	fi

	# Generate RSA root certificate
	echo -e "${GREYB}Generating root CA certificate...${GREY}"
	openssl req -config openssl.cnf -key private/ca.key.pem -new -x509 -days $CA_ROOT_DAYS -sha256 -extensions v3_ca -out certs/ca.cert.pem -passin pass:$CA_PW
	if [ $? -ne 0 ]; then
	echo -e "${RED}Failed. See ${LOG_LOCATION}${GREY}" 1>&2
	exit 1
	else
	echo -e "${LGREEN}OK${GREY}"
	echo
	fi

	# Generate RSA intermediate key
	echo -e "${GREYB}Generating intermediate CA key...${GREY}"
	openssl genrsa -aes256 -passout pass:$CA_PW -out intermediate/private/intermediate.key.pem 4096 
	chmod 400 intermediate/private/intermediate.key.pem
	if [ $? -ne 0 ]; then
	echo -e "${RED}Failed. See ${LOG_LOCATION}${GREY}" 1>&2
	exit 1
	else
	echo -e "${LGREEN}OK${GREY}"
	echo
	fi
fi

# EC specific actions #############################################################################################

if [[ "${ALGORITHM}" == "EC" ]]; then
	cd $CA_ROOT_DIR
	# Generate EC root private key with NIST recommended curve ECDSA P-384, and then encrypt it
	echo -e "${GREYB}Generating root key...${GREY}"
	openssl ecparam -name secp384r1 -genkey -noout -out private/ca-no-encrypt.key.pem
	openssl ec -aes256 -in private/ca-no-encrypt.key.pem -out private/ca.key.pem -passout pass:$CA_PW
	rm private/ca-no-encrypt.key.pem
	chmod 400 private/ca.key.pem
	if [ $? -ne 0 ]; then
	echo -e "${RED}Failed. See ${LOG_LOCATION}${GREY}" 1>&2
	exit 1
	else
	echo -e "${LGREEN}OK${GREY}"
	echo
	fi

	# Generate EC root certificate
	echo -e "${GREYB}Generating root CA certificate...${GREY}"
	openssl req -config openssl.cnf -key private/ca.key.pem -new -x509 -days $CA_ROOT_DAYS -sha256 -extensions v3_ca -out certs/ca.cert.pem -passin pass:$CA_PW
	if [ $? -ne 0 ]; then
	echo -e "${RED}Failed. See ${LOG_LOCATION}${GREY}" 1>&2
	exit 1
	else
	echo -e "${LGREEN}OK${GREY}"
	echo
	fi
	
	# Generate EC intermediate key
	echo -e "${GREYB}Generating intermediate CA key...${GREY}"
	openssl ecparam -name secp384r1 -genkey -noout -out intermediate/private/intermediate-no-encrpyt.key.pem
	openssl ec -aes256 -in intermediate/private/intermediate-no-encrpyt.key.pem -out intermediate/private/intermediate.key.pem -passout pass:$CA_PW
	rm intermediate/private/intermediate-no-encrpyt.key.pem
	chmod 400 intermediate/private/intermediate.key.pem
	if [ $? -ne 0 ]; then
	echo -e "${RED}Failed. See ${LOG_LOCATION}${GREY}" 1>&2
	exit 1
	else
	echo -e "${LGREEN}OK${GREY}"
	echo
	fi
fi

# RSA or EC CA creation actions #############################################################################################

	# Generate Intermediate CA csr
	echo -e "${GREYB}Generating intermediate CA certificate signing request...${GREY}"
	openssl req -config intermediate/openssl.cnf -new -sha256 -key intermediate/private/intermediate.key.pem -out intermediate/csr/intermediate.csr.pem -passin pass:$CA_PW
	if [ $? -ne 0 ]; then
	echo -e "${RED}Failed. See ${LOG_LOCATION}${GREY}" 1>&2
	exit 1
	else
	echo -e "${LGREEN}OK${GREY}"
	echo
	fi

	# Generate Intermediate CA
	echo -e "${GREYB}Generating the new intermediate CA certificate...${GREY}"
	openssl ca -config openssl.cnf -extensions v3_intermediate_ca -days $CA_INT_DAYS -notext -md sha256 -in intermediate/csr/intermediate.csr.pem -out intermediate/certs/intermediate.cert.pem -passin pass:$CA_PW
	if [ $? -ne 0 ]; then
	echo -e "${RED}Failed. See ${LOG_LOCATION}${GREY}" 1>&2
	exit 1
	else
	echo -e "${LGREEN}OK${GREY}"
	echo
	fi

	# The CA certificate chain comprises of the intermediate cert and the root cert (in that order)
	echo -e "${GREYB}Generating CA certificate chain file with root cert included (for standalone web servers)...${GREY}"
	cat intermediate/certs/intermediate.cert.pem certs/ca.cert.pem > intermediate/certs/ca-chain.cert.pem
	chmod 444 intermediate/certs/ca-chain.cert.pem
	if [ $? -ne 0 ]; then
	echo -e "${RED}Failed. See ${LOG_LOCATION}${GREY}" 1>&2
	exit 1
	else
	echo -e "${LGREEN}OK${GREY}"
	echo
	fi

	# A 2nd RSA CA chain option is to install the root certificate on every client, and have the chain file contain just the intermediate certificate
	echo -e "${GREYB}Generating CA certificate chain version without root cert (for intranet use)...${GREY}"
	cat intermediate/certs/intermediate.cert.pem > intermediate/certs/ca-chain-noroot.cert.pem
	chmod 444 intermediate/certs/ca-chain-noroot.cert.pem
	if [ $? -ne 0 ]; then
	echo -e "${RED}Failed. See ${LOG_LOCATION}${GREY}" 1>&2
	exit 1
	else
	echo -e "${LGREEN}OK${GREY}"
	fi

	sleep 4
	clear
;;


2)	# Add/update CRL support
	clear
	echo
	# Check for presence of CA base
	cd $CA_ROOT_DIR
	if [ "$( find . -maxdepth 4 \( -name 'ca.key.pem' -o -name 'ca.cert.pem' \) )" = "" ]; then
	echo
	echo -e "${LRED}CA base configuration not detected. Please check system status before continuing.${GREY}" 1>&2
	echo
	exit 1
	fi

	# Clear any previous CRL config
	sed -i "/crlDistributionPoints/d" $CA_INT_DIR/openssl.cnf

	# Prompt for CRL setup parameters
	while true; do
	read -p "Enter the URL of the certificate revocation list e.g. http://domain.com: " UPDATE_CRL
	[ "${UPDATE_CRL}" != "" ] && break
	echo -e "${LRED}You must enter the URL of the CRL. Please try again.${GREY}" 1>&2
	done

	# Add the new CRL value to the intermediate server cert policy
	sed -i "/insert_int_srv_revocation_options_below/a crlDistributionPoints = URI:${UPDATE_CRL}" $CA_INT_DIR/openssl.cnf

	# Setup and activate the CRL
	cd $CA_ROOT_DIR
	echo -e "${GREYB}Updating CRL configuration...${GREY}"
	openssl ca -config intermediate/openssl.cnf -gencrl -out intermediate/crl/intermediate.crl.pem
		if [ $? -ne 0 ]; then
	echo -e "${RED}Failed. See ${LOG_LOCATION}${GREY}" 1>&2
	exit 1
	else
	echo -e "${LGREEN}OK${GREY}"
	fi

	sleep 4
	clear
;;


3) # Add OCSP support
	clear
	echo
	# Check for presence of CA base
	cd $CA_ROOT_DIR
	if [ "$( find . -maxdepth 4 \( -name 'ca.key.pem' -o -name 'ca.cert.pem' \) )" = "" ]; then
	echo
	echo -e "${LRED}CA base configuration not detected. Please check system status before continuing.${GREY}" 1>&2
	echo
	exit 1
	fi

	# Clear any previous OCSP and CN config
	sed -i "/commonName_default/d" $CA_INT_DIR/openssl.cnf
	sed -i "/authorityInfoAccess/d" $CA_INT_DIR/openssl.cnf

	# Prompt for OCSP setup parameters
	while true; do
	read -p "Enter the full URL of the OCSP server e.g. http://domain.com: " UPDATE_OCSP_URL
	read -p "Enter (mandatory) FQDN of OCSP server certificate: " UPDATE_OCSP_FQDN
	echo
	[ "${UPDATE_OCSP_URL}" != "" ] && [ "${UPDATE_OCSP_FQDN}" != "" ] && break
	echo -e "${LRED}You must enter a valid OCSP URL and FQDN. Please try again.${GREY}" 1>&2
	done

	# Add the new OCSP value to the intermediate server cert policy
	sed -i "/insert_int_srv_revocation_options_below/a authorityInfoAccess = OCSP;URI:${UPDATE_OCSP_URL}" $CA_INT_DIR/openssl.cnf
	sed -i "/insert_common_name_below/a commonName_default              = ${UPDATE_OCSP_FQDN}" $CA_INT_DIR/openssl.cnf

# Create an OCSP start script (not essential, but handy for testing and troubleshooting)
cat <<EOF | tee $CA_ROOT_DIR/startOCSP.sh &>> ${LOG_LOCATION}
!/bin/bash
# manually run the responder
openssl ocsp -port 2560 -text -index $CA_ROOT_DIR/intermediate/index.txt -CA intermediate/certs/ca-chain.cert.pem -rkey intermediate/private/intermediate.ocsp.key.pem -rsigner intermediate/certs/intermediate.ocsp.cert.pem -nrequest 1
#Query the responder
# openssl ocsp -CAfile intermediate/certs/ca-chain.cert.pem -url http://127.0.0.1:2560 -resp_text -issuer intermediate/certs/intermediate.cert.pem -cert intermediate/certs/${REVOKE_OCSP}
EOF
	chmod +x $CA_ROOT_DIR/startOCSP.sh

# RSA specific actions ############################################################################################

	# Setup and activate OCSP
	cd $CA_ROOT_DIR
	if [[ "${ALGORITHM}" = "RSA" ]]; then
	openssl genrsa -aes256 -out intermediate/private/intermediate.ocsp.key.pem 4096
	openssl req -config intermediate/openssl.cnf -new -sha256 -key intermediate/private/intermediate.ocsp.key.pem -out intermediate/csr/intermediate.ocsp.csr.pem
	openssl ca -config intermediate/openssl.cnf -extensions ocsp -days $CA_INT_DAYS -notext -md sha256 -in intermediate/csr/intermediate.ocsp.csr.pem -out intermediate/certs/intermediate.ocsp.cert.pem
	if [ $? -ne 0 ]; then
	echo -e "${RED}Failed. See ${LOG_LOCATION}${GREY}" 1>&2
	exit 1
	else
	echo -e "${LGREEN}OK${GREY}"
	fi

fi

# EC specific actions #############################################################################################

	# Setup and activate OCSP
	if [[ "${ALGORITHM}" == "EC" ]]; then
	cd $CA_ROOT_DIR

## EC COMMANDS HERE

	if [ $? -ne 0 ]; then
	echo -e "${RED}Failed. See ${LOG_LOCATION}${GREY}" 1>&2
	exit 1
	else
	echo -e "${LGREEN}OK${GREY}"
	fi
fi

	sleep 4
	clear


;;


4)	# Create new server certificate
	clear
	echo
	# Check for presence of CA base
	cd $CA_ROOT_DIR
	if [ "$( find . -maxdepth 4 \( -name 'ca.key.pem' -o -name 'ca.cert.pem' \) )" = "" ]; then
	echo
	echo -e "${LRED}CA base configuration not detected. Please check system status before continuing.${GREY}" 1>&2
	echo
	exit 1
	fi

	# In case a previous certificate task was halted midway, clear out any previous CN and wildcard config 
	sed -i "/commonName_default/d" $CA_INT_DIR/openssl.cnf
	sed -i "/DNS.1/d" $CA_INT_DIR/openssl.cnf
	while true; do
	read -p "Enter the (mandatory) FQDN for the new SERVER certificate: " CERT_NAME_SRV
	[ "${CERT_NAME_SRV}" != "" ] && break
	echo -e "${LRED}You must enter a server certificate DNS name. Please try again.${GREY}" 1>&2
	done

	# check to make sure another server pair with the same name does not exist.
	cd $CA_INT_DIR
	if [ "$( find . -maxdepth 4 \( -name "${CERT_NAME_SRV}.key.pem" -o -name "${CERT_NAME_SRV}.cert.pem" \) )" != "" ]; then
	echo -e "${LRED}	Danger! Identically named certificate detected. Please review before continuing.${GREY}" 1>&2
	echo
	exit 1
	fi

	# CN must be a FQDN for server certs, so temporarily add this custom value to the default intermediate cert policy
	sed -i "/insert_common_name_below/a commonName_default              = ${CERT_NAME_SRV}" $CA_INT_DIR/openssl.cnf

	# Add dns wild card temporarily to the default intermediate cert policy
	sed -i "/insert_int_srv_dns_name_below/a DNS.1                 = *.${CERT_NAME_SRV}" $CA_INT_DIR/openssl.cnf


# RSA specific actions ############################################################################################

	# Create RSA server certificate pair
	if [[ "${ALGORITHM}" = "RSA" ]]; then
	# Create a new server private key
	cd $CA_ROOT_DIR
	if [[ "${CERT_PW}" = "true" ]]; then
	openssl genrsa -aes256 -out intermediate/private/$CERT_NAME_SRV.key.pem 2048 # use this line to require a server cert password
	else
	openssl genrsa -out intermediate/private/$CERT_NAME_SRV.key.pem 2048
	fi
	chmod 400 intermediate/private/$CERT_NAME_SRV.key.pem

	# Create a new CSR
	openssl req -config intermediate/openssl.cnf -key intermediate/private/$CERT_NAME_SRV.key.pem -new -sha256 -out intermediate/csr/$CERT_NAME_SRV.csr.pem

	# Create a new server certificate
	openssl ca -config intermediate/openssl.cnf -extensions server_cert -days $CERT_DAYS -notext -md sha256 -in intermediate/csr/$CERT_NAME_SRV.csr.pem -out intermediate/certs/$CERT_NAME_SRV.cert.pem
	chmod 444 intermediate/certs/$CERT_NAME_SRV.cert.pem

	# Remove custom the CN and DNS wildcard value from the default intermediate cert policy
	sed -i "/commonName_default/d" $CA_INT_DIR/openssl.cnf
	sed -i "/DNS.1/d" $CA_INT_DIR/openssl.cnf

	# Copy the completed certificate files to the user's home directory for easy extraction
	mkdir -p $USER_HOME_DIR/$CERT_NAME_SRV
	cp $CA_ROOT_DIR/intermediate/private/$CERT_NAME_SRV.key.pem $USER_HOME_DIR/$CERT_NAME_SRV
	cp $CA_ROOT_DIR/intermediate/certs/$CERT_NAME_SRV.cert.pem $USER_HOME_DIR/$CERT_NAME_SRV
	cp $CA_ROOT_DIR/intermediate/certs/ca-chain.cert.pem $USER_HOME_DIR/$CERT_NAME_SRV
	cp $CA_ROOT_DIR/intermediate/certs/ca-chain-noroot.cert.pem $USER_HOME_DIR/$CERT_NAME_SRV
	if [ $? -ne 0 ]; then
	echo -e "${RED}Failed. See ${LOG_LOCATION}${GREY}" 1>&2
	exit 1
	else
	echo -e "${LGREEN}OK${GREY}"
	echo
	fi

	echo -e "${GREYB}New certificate files have been copied to $USER_HOME_DIR/$CERT_NAME_SRV${GREY}"

	fi

# EC specific actions #############################################################################################

	# Create EC server certificate pair
	if [[ "${ALGORITHM}" = "EC" ]]; then
	# Create a new server private key
	cd $CA_ROOT_DIR
	# use this line to require a server cert password
	#
	# Create a new CSR

	# Create a new server certificate

	# Remove custom the CN and DNS wildcard value from the default intermediate cert policy

	# Copy the completed certificate files to the user's home directory for easy extraction
	fi

	sleep 4
	clear

;;


5)	# Prompt for new user SSL certificate creation
	clear
	echo
	# Check for presence of CA base
	cd $CA_ROOT_DIR
	if [ "$( find . -maxdepth 4 \( -name 'ca.key.pem' -o -name 'ca.cert.pem' \) )" = "" ]; then
	echo
	echo -e "${LRED}CA base configuration not detected. Please check system status before continuing.${GREY}" 1>&2
	echo
	exit 1
	fi

	# Clear out any previous CN config
	sed -i "/commonName_default/d" $CA_INT_DIR/openssl.cnf
	while true; do
	read -p "Enter a unique name for the new USER certificate: " CERT_NAME_USR
	[ "${CERT_NAME_USR}" != "" ] && break
	echo -e "${LRED}You must enter a unique name for the user certificate. Please try again.${GREY}" 1>&2
	done

	# Check to make sure another user pair with the same name does not exist with the intermediate CA.
	cd $CA_INT_DIR
	if [ "$( find . -maxdepth 4 \( -name "${CERT_NAME_USR}.key.pem" -o -name "${CERT_NAME_USR}.cert.pem" \) )" != "" ]; then
	echo -e "${LRED}Danger! Identically named certificate detected. Please review before continuing.${GREY}" 1>&2
	echo
	exit 1
	fi

	# Temporarily add the user cert name to the default intermediate cert policy
	sed -i "/insert_common_name_below/a commonName_default              = ${CERT_NAME_USR}" $CA_INT_DIR/openssl.cnf


# RSA specific actions ############################################################################################

	# Create RSA user certificate pair
	if [[ "${ALGORITHM}" = "RSA" ]]; then

	# Create a new user private key
	cd $CA_ROOT_DIR
	if [[ "${CERT_PW}" = "true" ]]; then
	openssl genrsa -aes256 -out intermediate/private/$CERT_NAME_USR.key.pem 2048 # require a cert password
	else
	openssl genrsa -out intermediate/private/$CERT_NAME_USR.key.pem 2048
	fi
	chmod 400 intermediate/private/$CERT_NAME_USR.key.pem

	# Create a new CSR
	openssl req -config intermediate/openssl.cnf -key intermediate/private/$CERT_NAME_USR.key.pem -new -sha256 -out intermediate/csr/$CERT_NAME_USR.csr.pem

	# Create a new user certificate
	openssl ca -config intermediate/openssl.cnf -extensions usr_cert -days $CERT_DAYS -notext -md sha256 -in intermediate/csr/$CERT_NAME_USR.csr.pem -out intermediate/certs/$CERT_NAME_USR.cert.pem
	chmod 444 intermediate/certs/$CERT_NAME_USR.cert.pem

	# Remove the CN value from the default intermediate cert policy
	sed -i "/commonName_default/d" $CA_INT_DIR/openssl.cnf

	# Copy the completed certificate files to the user's home directory for easy extraction
	mkdir -p $USER_HOME_DIR/$CERT_NAME_USR
	cp $CA_ROOT_DIR/intermediate/private/$CERT_NAME_USR.key.pem $USER_HOME_DIR/$CERT_NAME_USR
	cp $CA_ROOT_DIR/intermediate/certs/$CERT_NAME_USR.cert.pem $USER_HOME_DIR/$CERT_NAME_USR
	cp $CA_ROOT_DIR/intermediate/certs/ca-chain.cert.pem $USER_HOME_DIR/$CERT_NAME_USR
	cp $CA_ROOT_DIR/intermediate/certs/ca-chain-noroot.cert.pem $USER_HOME_DIR/$CERT_NAME_USR
	if [ $? -ne 0 ]; then
	echo -e "${RED}Failed. See ${LOG_LOCATION}${GREY}" 1>&2
	exit 1
	else
	echo -e "${LGREEN}OK${GREY}"
	echo
	fi

	echo -e "${GREYB}New certificate files have been copied to $USER_HOME_DIR/$CERT_NAME_USR${GREY}"

fi

# EC specific actions #############################################################################################

	if [[ "${ALGORITHM}" = "EC" ]]; then
	# Create a new user private key
	cd $CA_ROOT_DIR
	# use this line to require a server cert password
	#
	# Create a new CSR

	# Create a new server certificate

	# Remove the CN value from the default intermediate cert policy

	# Copy the completed certificate files to the user's home directory for easy extraction
	fi

	sleep 4
	clear

;;


6) # Revoke certificate via CRL
	clear
	echo
	# Check for presence of CRL config
	cd $CA_ROOT_DIR
	if [ "$( find . -maxdepth 4 \( -name 'intermediate.crl.pem' \) )" = "" ]; then
	echo
	echo -e "${LRED}CRL configuration not detected. Please check system status before continuing.${GREY}" 1>&2
	echo
	exit 1
	fi

	cd $CA_ROOT_DIR
	while true; do
	read -p "Enter the certificate name (filename) to revoke via CRL (e.g. dns-or-unique-name.cert.pem): " REVOKE_CRL
	[ "${REVOKE_CRL}" != "" ] && break
	echo -e "${LRED}You must enter a valid certificate name. Please try again.${GREY}" 1>&2
	done

	# Execute the CRL revocation
	openssl ca -config intermediate/openssl.cnf -revoke intermediate/certs/${REVOKE_CRL}

	sleep 4
	clear
;;


7) # Revoke certificate via OCSP
	clear
	echo
	# Check for presence of OCSP config
	cd $CA_ROOT_DIR
	if [ "$( find . -maxdepth 4 \( -name 'intermediate.ocsp.key.pem' -o -name 'intermediate.ocsp.key.pem' \) )" = "" ]; then
	echo
	echo -e "${LRED}OCSP configuration not detected. Please check system status before continuing.${GREY}" 1>&2
	echo
	exit 1
	fi

	cd $CA_ROOT_DIR
	while true; do
	read -p "Enter the certificate name (filename) to revoke via OSCP (e.g. dns-or-unique-name.cert.pem): " REVOKE_OCSP
	[ "${REVOKE_OCSP}" != "" ] && break
	echo -e "${LRED}You must enter a valid certificate name. Please try again.${GREY}" 1>&2
	done

	# Execute the OCSP revocation
	openssl ca -config intermediate/openssl.cnf -revoke intermediate/certs/${REVOKE_OCSP}

	# Stop ocsp, (subsequent revocations are unable to bind to an already running socket)
	PID=`ps aux | grep "ocsp" | grep -v 'grep' | awk '{ print $2 }'`
	# Now lets kill all of the PIDs from the list
	for P in $PID; do
		echo "Killing $P"
	kill -9 $P
	done

	sleep 4
	clear
;;


	8) # Exit script
	echo
	break
;;


	*)
	echo "Invalid choice"
	clear
;;
	esac
done




