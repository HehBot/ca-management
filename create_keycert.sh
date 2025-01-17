#!/bin/bash
#
# written with the help of
#   https://jamielinux.com/docs/openssl-certificate-authority
#

usage_exit () {
    echo "Usage: $0 (newServerKeyCert|newClientKeyCert) <CA dir> <CN> [CA passfile]"
    exit 0
}

if ! [[ $# -eq 3 ]] && ! [[ $# -eq 4 ]]; then
    usage_exit
fi

if [[ "$1" == "newServerKeyCert" ]]; then
    PURPOSE=server_cert
elif [[ "$1" == "newClientKeyCert" ]]; then
    PURPOSE=usr_cert
else
    usage_exit
fi
CA_DIR="$2"
CA_CONF="${CA_DIR}/openssl.conf"
CN="$3"
CA_PASSIN="stdin"
if [[ $# -eq 4 ]]; then
    CA_PASSIN="file:$4"
fi

if ! [[ -f "${CA_DIR}/cn" ]]; then
    echo "CA not found (searched for file '${CA_DIR}/cn')"
    exit 1
fi

CA_CN="$(cat ${CA_DIR}/cn)"

if [[ "${CN}" == "${CA_CN}" ]]; then
    echo "Cannot create keycert with same CN as CA"
    exit 1
fi

KEY="${CA_DIR}/private/${CN}.key.pem"
if [[ -f "${KEY}" ]]; then
    echo "Key for '${CN}' (file '${KEY}') already exists!"
    exit 1
fi

# create new key
openssl genrsa -out "${KEY}" 2048
chmod 400 "${KEY}"

# create certificate
CSR="$(mktemp)"
openssl req -config "${CA_CONF}" \
    -key "${KEY}" \
    -subj "/C=IN/ST=Maharashtra/O=coffre/CN=${CN}" \
    -new -sha256 -out "${CSR}"

# have intermediate CA sign the certificate
CERT="${CA_DIR}/certs/${CN}.cert.pem"
if [[ "${CA_PASSIN}" == "stdin" ]]; then
    read -sp "Enter the passphrase of the CA: " CA_PASSPHRASE; echo
    export CA_PASSPHRASE
    CA_PASSIN="env:CA_PASSPHRASE"
fi
openssl ca -config "${CA_CONF}" \
    -extensions "${PURPOSE}" -days 375 -notext -md sha256 \
    -passin "${CA_PASSIN}" \
    -batch \
    -in "${CSR}" \
    -out "${CERT}"
if [[ $? != 0 ]]; then
    echo "Error, see above"
    X=$?
    rm -rf "${KEY}" "${CSR}" "${CERT}"
    exit $X
fi
chmod 444 "${CERT}"

# generate certificate chain
CHAIN_CERT="${CA_DIR}/certs/${CN}.chain.cert.pem"
cat "${CERT}" "${CA_DIR}/certs/${CA_CN}.chain.cert.pem" > "${CHAIN_CERT}"

echo "New key:        ${KEY}"
echo "New chain cert: ${CHAIN_CERT}"
