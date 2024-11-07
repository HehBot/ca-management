#!/bin/bash
#
# written with the help of
#   https://jamielinux.com/docs/openssl-certificate-authority
#

checkerr () {
    if [[ $? != 0 ]]; then
        echo "Error, see above"
        rm -rf "${CA_DIR}"
        exit 2
    fi
}

CONF_TEMPLATE='
[ ca ]
# `man ca`
default_ca = CA_default

[ CA_default ]
# Directory and file locations.
dir               = XXXXDIRXXXX
certs             = $dir/certs
crl_dir           = $dir/crl
new_certs_dir     = $dir/newcerts
database          = $dir/index.txt
serial            = $dir/serial
RANDFILE          = $dir/private/.rand

# The key and certificate.
private_key       = $dir/private/XXXXCNXXXX.key.pem
certificate       = $dir/certs/XXXXCNXXXX.cert.pem

# For certificate revocation lists.
crlnumber         = $dir/crlnumber
crl               = $dir/crl/XXXXCNXXXX.crl.pem
crl_extensions    = crl_ext
default_crl_days  = 30

# SHA-1 is deprecated, so use SHA-2 instead.
default_md        = sha256

name_opt          = ca_default
cert_opt          = ca_default
default_days      = 375
preserve          = no
policy            = policy_strict

[ policy_strict ]
# The CA should only sign certificates that match.
# See the POLICY FORMAT section of `man ca`.
countryName             = match
stateOrProvinceName     = match
organizationName        = match
organizationalUnitName  = optional
commonName              = supplied
emailAddress            = optional

[ req ]
# Options for the `req` tool (`man req`).
default_bits        = 2048
distinguished_name  = req_distinguished_name
string_mask         = utf8only

# SHA-1 is deprecated, so use SHA-2 instead.
default_md          = sha256

[ req_distinguished_name ]
# See <https://en.wikipedia.org/wiki/Certificate_signing_request>.
countryName                     = Country Name (2 letter code)
stateOrProvinceName             = State or Province Name
localityName                    = Locality Name
0.organizationName              = Organization Name
organizationalUnitName          = Organizational Unit Name
commonName                      = Common Name
emailAddress                    = Email Address

[ v3_ca ]
# Extensions for a typical CA (`man x509v3_config`).
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid:always,issuer
basicConstraints = critical, CA:true
keyUsage = critical, digitalSignature, cRLSign, keyCertSign

[ v3_intermediate_ca ]
# Extensions for a typical intermediate CA (`man x509v3_config`).
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid:always,issuer
basicConstraints = critical, CA:true, pathlen:0
keyUsage = critical, digitalSignature, cRLSign, keyCertSign

[ usr_cert ]
# Extensions for client certificates (`man x509v3_config`).
basicConstraints = CA:FALSE
nsCertType = client, email
nsComment = "OpenSSL Generated Client Certificate"
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid,issuer
keyUsage = critical, nonRepudiation, digitalSignature, keyEncipherment
extendedKeyUsage = clientAuth, emailProtection

[ server_cert ]
# Extensions for server certificates (`man x509v3_config`).
basicConstraints = CA:FALSE
nsCertType = server
nsComment = "OpenSSL Generated Server Certificate"
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid,issuer:always
keyUsage = critical, digitalSignature, keyEncipherment
extendedKeyUsage = serverAuth

[ crl_ext ]
# Extension for CRLs (`man x509v3_config`).
authorityKeyIdentifier=keyid:always

[ ocsp ]
# Extension for OCSP signing certificates (`man ocsp`).
basicConstraints = CA:FALSE
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid,issuer
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, OCSPSigning
'

# sets CA_DIR,CA_CN,CA_CONF,CA_KEY
common_setup () {
    CA_DIR="$(realpath "$1")"
    checkerr
    CA_CN="$2"
    if [[ -d "${CA_DIR}" ]]; then
        echo "Directory ${CA_DIR} already exists, delete it and try again"
        exit 1
    fi
    mkdir "${CA_DIR}"

    echo "${CA_CN}" > "${CA_DIR}/cn"

    CA_CONF="${CA_DIR}/openssl.conf"
    echo "${CONF_TEMPLATE}" > "${CA_CONF}"
    sed -i "s~XXXXDIRXXXX~${CA_DIR}~g" "${CA_CONF}"
    sed -i "s~XXXXCNXXXX~${CA_CN}~g" "${CA_CONF}"

    mkdir -p "${CA_DIR}"/{certs,crl,csr,newcerts,private}
    chmod 700 "${CA_DIR}/private"
    touch "${CA_DIR}/index.txt"
    echo 1000 > "${CA_DIR}/serial"
    echo 1000 > "${CA_DIR}/crlnumber"

    # create key
    CA_KEY="${CA_DIR}/private/${CA_CN}.key.pem"
    echo
    echo "You will now be prompted to create a passphrase for the CA"
    openssl genrsa -aes256 -out "${CA_KEY}" 4096
    checkerr
    chmod 400 "${CA_KEY}"
}

new_root_ca () {
    common_setup "$1" "$2"

    # create cert
    CA_CERT="${CA_DIR}/certs/${CA_CN}.cert.pem"
    echo
    echo "You will now be prompted for the passphrase of the CA"
    openssl req -config "${CA_CONF}" -key "${CA_KEY}" \
        -new -x509 -days 7300 -sha256 -extensions v3_ca \
        -subj "/C=IN/ST=Maharashtra/O=coffre/CN=${CA_CN}" \
        -out "${CA_CERT}"
    checkerr
    chmod 444 "${CA_CERT}"
    CA_CHAIN_CERT="${CA_DIR}/certs/${CA_CN}.chain.cert.pem"
    cp "${CA_CERT}" "${CA_CHAIN_CERT}"
}

new_non_root_ca() {
    PARENT_CA_DIR="$3"
    PARENT_CA_CONF="${PARENT_CA_DIR}/openssl.conf"
    if ! [[ -f "${PARENT_CA_CONF}" ]] || ! [[ -f "${PARENT_CA_DIR}/cn" ]]; then
        echo "Parent CA not found (searched for files '${PARENT_CA_CONF}', '${PARENT_CA_DIR}/cn')"
        exit 1
    fi
    PARENT_CA_CN="$(cat "${PARENT_CA_DIR}/cn")"

    common_setup "$1" "$2"

    # create csr
    CA_CSR="${CA_DIR}/csr/${CA_CN}.csr.pem"
    echo
    echo "You will now be prompted for the passphrase of the CA"
    openssl req -config "${CA_CONF}" -new -sha256 \
        -key "${CA_KEY}" \
        -subj "/C=IN/ST=Maharashtra/O=coffre/CN=${CA_CN}" \
        -out "${CA_CSR}"

    # create cert
    CA_CERT="${CA_DIR}/certs/${CA_CN}.cert.pem"
    echo
    echo "You will now be prompted for the passphrase of the parent CA"
    openssl ca -config "${PARENT_CA_CONF}" -extensions v3_intermediate_ca \
        -days 3650 -notext -md sha256 \
        -batch \
        -in "${CA_CSR}" \
        -out "${CA_CERT}"
    checkerr
    chmod 444 "${CA_CERT}"

    # create cert chain
    PARENT_CA_CHAIN_CERT="${PARENT_CA_DIR}/certs/${PARENT_CA_CN}.chain.cert.pem"
    CA_CHAIN_CERT="${CA_DIR}/certs/${CA_CN}.chain.cert.pem"
    cat "${CA_CERT}" "${PARENT_CA_CHAIN_CERT}" > "${CA_CHAIN_CERT}"
    chmod 444 "${CA_CHAIN_CERT}"

    # create crl
    CA_CRL="${CA_DIR}/crl/${CA_CN}.crl.pem"
    echo
    echo "You will now be prompted for the passphrase of the CA"
    openssl ca -config "${CA_CONF}" -gencrl \
        -out "${CA_CRL}"
    checkerr
}

if [[ $# == 3 ]] && [[ "$1" == "newRootCA" ]]; then
    new_root_ca "$2" "$3"
    exit 0
elif [[ $# == 4 ]] && [[ "$1" == "newNonRootCA" ]]; then
    new_non_root_ca "$2" "$3" "$4"
    exit 0
else
    echo "Usage: $0 newRootCA <CA dir to create> <CA CN>"
    echo "Usage: $0 newNonRootCA <CA dir to create> <CA CN> <parent CA dir>"
    exit 1
fi
