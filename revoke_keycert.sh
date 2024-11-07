#!/bin/bash
#
# written with the help of
#   https://jamielinux.com/docs/openssl-certificate-authority/index.html
#

if ! [[ $# -eq 2 ]]; then
    echo "Usage: $0 <CA dir> <CN>"
    exit 0
fi

checkerr () {
    if [[ $? != 0 ]]; then
        X=$?
        echo "Error, see above"
        exit $X
    fi
}

CA_DIR="$1"
CA_CONF="${CA_DIR}/openssl.conf"
CN="$2"

if ! [[ -f "${CA_DIR}/cn" ]]; then
    echo "CA not found (searched for file '${CA_DIR}/cn')"
    exit 1
fi

CA_CN="$(cat ${CA_DIR}/cn)"

if [[ "${CN}" == "${CA_CN}" ]]; then
    echo "Cannot revoke CA's own certificate"
    exit 1
fi

CERT="${CA_DIR}/certs/${CN}.cert.pem"
if ! [[ -f "${CERT}" ]]; then
    echo "Certificate for '${CN}' not found (searched for file '${CERT}')"
    exit 1
fi

# revoke cert
openssl ca -config "${CA_CONF}" \
    -revoke "${CERT}"
# should always regenerate CRL, so no checkerr

# create crl
CA_CRL="${CA_DIR}/crl/${CA_CN}.crl.pem"
echo
echo "You will now be prompted for the passphrase of the CA"
openssl ca -config "${CA_CONF}" -gencrl \
    -out "${CA_CRL}"
checkerr
