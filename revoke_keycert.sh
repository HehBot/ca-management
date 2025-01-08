#!/bin/bash
#
# written with the help of
#   https://jamielinux.com/docs/openssl-certificate-authority
#

if ! [[ $# -eq 2 ]] && ! [[ $# -eq 3 ]]; then
    echo "Usage: $0 <CA dir> <CN> [CA passfile]"
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
CA_PASSIN="stdin"
if [[ $# -eq 3 ]]; then
    CA_PASSIN="file:$3"
fi

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
if [[ "${CA_PASSIN}" == "stdin" ]]; then
    echo "Enter the passphrase of the CA"
fi
openssl ca -config "${CA_CONF}" \
    -passin "${CA_PASSIN}" \
    -revoke "${CERT}"
# should always regenerate CRL, so no checkerr

# create crl
CA_CRL="${CA_DIR}/crl/${CA_CN}.crl.pem"
if [[ "${CA_PASSIN}" == "stdin" ]]; then
    echo "Enter the passphrase of the CA"
fi
openssl ca -config "${CA_CONF}" -gencrl \
    -passin "${CA_PASSIN}" \
    -out "${CA_CRL}"
checkerr
