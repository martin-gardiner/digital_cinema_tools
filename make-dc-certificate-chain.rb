#!/usr/bin/env ruby
# Requires ruby and openssl
#
# Make a digital cinema compliant certificate chain
# Proof of concept. In real-world applications you'd want 
# to secure keys with passphrases and set up some infrastructure
# to allow for various intermediate and leaf certificates.
#
# Intentionally no ruby-specific openssl bindings here,
# merely building shell calls to openssl.
# Should make it easy to port to different environments.
#
# No directory and file checks here. Watch out where you run it.
#
# $ mkdir certificate-store
# $ cd certificate-store
# $ make-dc-certificate-chain.rb
#
# CTP: How to verify certificates and create a certificate chain file:
#
# $ openssl verify -CAfile ca.self-signed.pem ca.self-signed.pem
# ca.self-signed.pem: OK
# $ cp ca.self-signed.pem certificate_chain
# $ openssl verify -CAfile certificate_chain intermediate.signed.pem
# intermediate.signed.pem: OK
# $ cat intermediate.signed.pem >> certificate_chain
# $ openssl verify -CAfile certificate_chain leaf.signed.pem
# leaf.signed.pem: OK
# $ cat leaf.signed.pem >> certificate_chain
#
# Use leaf.signed.pem to sign files

# Clean up previous runs
old = Dir.glob( [ 'ca.*', 'inter.*', 'cs.*' ] )
old.each do |file|
  File.delete( file )
end

### Make a self-signed root certificate. This will act as trust anchor for your certificate chain
# Generate CA key
`openssl genrsa -out ca.key 2048`
# Note basicConstraints and keyUsage
ca_cnf = <<EOF
[ req ]
distinguished_name = req_distinguished_name
x509_extensions	= v3_ca
[ v3_ca ]
basicConstraints = critical,CA:true,pathlen:3
keyUsage = keyCertSign,cRLSign
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid:always,issuer:always
[ req_distinguished_name ]
O = Unique organization name
OU = Organization unit
CN = Entity and dnQualifier
EOF
File.open( 'ca.cnf', 'w' ) { |f| f.write( ca_cnf ) }
# Subject dnQualifier:
ca_dnq = `openssl rsa -outform PEM -pubout -in ca.key | openssl base64 -d | dd bs=1 skip=24 2>/dev/null | openssl sha1 -binary | openssl base64`.chomp
ca_dnq = ca_dnq.gsub( '/', '\/' ) # can have values like '0Za8/aABE05Aroz7le1FOpEdFhk=', note the '/'. protect for name parser
# The following simply concatenates the dnq. Somehow I have a feeling that that's not quite right. Someone knows?
ca_subject = '/O=example.com/OU=csc.example.com/CN=dcstore.ROOT/dnQualifier=' + ca_dnq
# Generate self-signed certificate
`openssl req -new -x509 -sha256 -config ca.cnf -days 365 -set_serial 5 -subj "#{ ca_subject }" -key ca.key -outform PEM -out ca.self-signed.pem`
###

### Make an intermediate certificate, issued/signed by the root certificate
# Generate intermediate's key
`openssl genrsa -out intermediate.key 2048`
# Note basicConstraints pathlen
inter_cnf = <<EOF
[ default ]
distinguished_name	= req_distinguished_name
x509_extensions	= v3_ca
[ v3_ca ]
basicConstraints = critical,CA:true,pathlen:2
keyUsage = keyCertSign,cRLSign
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid:always,issuer:always
[ req_distinguished_name ]
O = Unique organization name
OU = Organization unit
CN = Entity and dnQualifier
EOF
File.open( 'intermediate.cnf', 'w' ) { |f| f.write( inter_cnf ) }
inter_dnq = `openssl rsa -outform PEM -pubout -in intermediate.key | openssl base64 -d | dd bs=1 skip=24 2>/dev/null | openssl sha1 -binary | openssl base64`.chomp
inter_dnq = inter_dnq.gsub( '/', '\/' )
inter_subject = "/O=example.com/OU=csc.example.com/CN=dcstore.INTERMEDIATE/dnQualifier=" + inter_dnq
# Request signing for intermediate certificate
`openssl req -new -config intermediate.cnf -days 365 -subj "#{ inter_subject }" -key intermediate.key -out intermediate.csr`
# Sign with root certificate
`openssl x509 -req -sha256 -days 365 -CA ca.self-signed.pem -CAkey ca.key -set_serial 6 -in intermediate.csr -extfile intermediate.cnf -extensions v3_ca -out intermediate.signed.pem`
###

### Make a leaf certificate, issued/signed by the intermediate certificate. Use the leaf certificate to sign content (like CPLs and PKLs)
# Generate leaf's key
`openssl genrsa -out leaf.key 2048`
# Note basicConstraints and keyUsage
leaf_cnf = <<EOF
[ default ]
distinguished_name	= req_distinguished_name
x509_extensions	= v3_ca
[ v3_ca ]
basicConstraints = critical,CA:false,pathlen:0
keyUsage = digitalSignature,keyEncipherment
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid,issuer:always
[ req_distinguished_name ]
O = Unique organization name
OU = Organization unit
CN = Entity and dnQualifier
EOF
File.open( 'leaf.cnf', 'w' ) { |f| f.write( leaf_cnf ) }
leaf_dnq = `openssl rsa -outform PEM -pubout -in leaf.key | openssl base64 -d | dd bs=1 skip=24 2>/dev/null | openssl sha1 -binary | openssl base64`.chomp
leaf_dnq = leaf_dnq.gsub( '/', '\/' )
# Note the CN role signifier CS (Content signer/creator)
leaf_subject = "/O=example.com/OU=csc.example.com/CN=CS dcstore.LEAF/dnQualifier=" + leaf_dnq
# Request signing for leaf certificate
`openssl req -new -config leaf.cnf -days 365 -subj "#{ leaf_subject }" -key leaf.key -outform PEM -out leaf.csr`
# Sign with intermediate certificate
`openssl x509 -req -sha256 -days 365 -CA intermediate.signed.pem -CAkey intermediate.key -set_serial 7 -in leaf.csr -extfile leaf.cnf -extensions v3_ca -out leaf.signed.pem`
###

### Print out issuer and subject information for each of the generated certificates
puts "\n+++ Certificate info +++\n"
[ [ 'Self-signed CA certificate (issuer == subject)', 'ca.self-signed.pem' ], [ 'Intermediate certificate', 'intermediate.signed.pem' ], [ 'Leaf certificate', 'leaf.signed.pem' ] ].each do |certificate|
  puts "\n#{ certificate.first } (#{ certificate.last }):\n#{ `openssl x509 -noout -subject -in #{ certificate.last }` }   signed by\n #{ `openssl x509 -noout -issuer -in #{ certificate.last }` }"
end

