#!/usr/bin/env ruby
#
# Wolfgang Woehl v0.2011.11.25
#
# Validate XML document against XSD.
# Quick and dirty. Thank you, libxml and nokogiri!
#
# xsd-check.rb <Schema file> <XML document>
# xsd-check.rb SMPTE-429-7-2006-CPL.xsd cpl.xml
#

require 'rubygems'
require 'nokogiri'

if ARGV.size == 2
  args = ARGV
  if args.first == args.last
    puts "Identical files provided"
    exit
  end
else
  puts "2 arguments required: 1 XML file, 1 XSD file (Order doesn't matter)"
  exit
end

if ENV[ 'XML_CATALOG_FILES' ].nil?
  puts 'Consider using XML Catalogs and set env XML_CATALOG_FILES to point at your catalog'
end

errors = Array.new
schema = ''
doc = ''

args.each do |arg|
  begin
    xml = Nokogiri::XML( open arg )
  rescue Exception => e
    puts e.message
    exit
  end
  unless xml.errors.empty?
    xml.errors.each do |e|
      puts "Syntax error: #{ arg }: #{ e }"
      errors << e
    end
  end
  case xml.root.node_name
  when 'schema'
    schema = arg
  else
    doc = arg
  end
end
exit if ! errors.empty?

xsd = Nokogiri::XML::Schema( open schema )
schema_errors = xsd.validate( doc )
if ! schema_errors.empty?
  schema_errors.each do |error|
    errors << error
    puts "Validation: #{ doc }: #{ error.message }"
  end
else
  puts "XML document is valid"
end

if ! errors.empty?
  errors.each do |e|
    if e.message.match /Element.*No matching global declaration available/
      puts 'Wrong XSD file?'
    end
  end
  puts "XML document is not valid"
end

