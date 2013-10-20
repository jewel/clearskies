#!/usr/bin/ruby -w
# Use UPNP to open a port on the firewall
#
# This is a pure-ruby implementation of the bare-minimum portions of UPNP
# necessary to open a port in the firewall.

require 'socket'
require 'timeout'
require 'net/http'
require 'uri'
require 'rexml/document'
require 'rexml/xpath'

class UPnP
  DURATION = 600

  def initialize port
    Thread.new do
      loop do
        begin
          open( 'TCP', port, port )
        rescue
          puts "Problem in UPnP: #{$!}"
        end
        sleep DURATION + 1
      end
    end
  end

  def open protocol, external_port, internal_port
    udp = UDPSocket.new
    search_str = <<EOF
M-SEARCH * HTTP/1.1
Host: 239.255.255.250:1900
Man: "ssdp:discover"
ST: upnp:rootdevice
MX: 3

EOF
    search_str.gsub! "\n", "\r\n"
    udp.send search_str, 0, "239.255.255.250", 1900 )
    responses = []
    begin
      # FIXME this timeout might need to be bigger for some routers
      timeout( 1 ) do
        loop do
          responses.push udp.recv( 4096 )
        end
      end
    rescue Timeout::Error
    end

    if responses.size == 0
      raise "No UPnP root devices found"
    end
    responses.each do |resp|
      next unless resp =~ /^Location: (http:\/\/.*?)\r\n/
      url = URI.parse( $1 )
      res = Net::HTTP.start( url.host, url.port ) { |http|
        http.get(url.request_uri)
      }
      if !res.is_a? Net::HTTPSuccess
        puts "UPnP warning: Could not fetch description XML at #{url}"
        next
      end
      doc = REXML::Document.new res.body
      doc.elements.each( "//service" ) do |service|
        next unless service.elements["serviceType"].text == "urn:schemas-upnp-org:service:WANCommonInterfaceConfig:1"
        control = service.elements["controlURL"].text
        if control !~ /^http:\/\//
          control = "http://#{url.host}:#{url.port}#{control}"
        end

        namespace = "device:InternetGatewayDevice:1"
        data = soap( control, namespace, :GetExternalIPAddress, "" )

        data = REXML::Document.new( data )
        external_ip = REXML::XPath.first( data, "//NewExternalIPAddress/text()" )
        external_ip = external_ip.to_s
        if external_ip =~ /^[\d\.]+$/
          puts "UPnP: External IP is #{external_ip}"
        end

        uri = URI.parse control

        # we don't actually connect, but by pretending to do so we see what our
        # source address would be for connecting out to the host
        udp.connect uri.host, uri.port

        internal_ip = udp.addr[3]
        raise "Cannot discover local IP address" unless internal_ip

        namespace = "service:WANIPConnection:1"
        next unless soap( control, namespace, :AddPortMapping, <<EOF )
<NewRemoteHost></NewRemoteHost>
<NewExternalPort>#{external_port}</NewExternalPort>
<NewProtocol>#{protocol}</NewProtocol>
<NewInternalPort>#{internal_port}</NewInternalPort>
<NewInternalClient>#{internal_ip}</NewInternalClient>
<NewEnabled>1</NewEnabled>
<NewPortMappingDescription>upnp-ruby (#{internal_ip}:#{internal_port}) #{external_port} #{protocol}</NewPortMappingDescription>
<NewLeaseDuration>#{DURATION}</NewLeaseDuration>
EOF

        puts "UPnP router #{url.host} is forwarding #{external_port} to #{internal_ip}:#{internal_port}, expires in #{DURATION} s."
      end
    end
  end

  UPNP_NS = "urn:schemas-upnp-org"

  def soap url, ns, method, content
    ns = UPNP_NS + ":" + ns
    uri = URI.parse url
    body = <<EOF
<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/"
  s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">
<s:Body>
<u:#{method} xmlns:u="#{ns}">
#{content}
</u:#{method}>
</s:Body>
</s:Envelope>
EOF
    headers = {
        "HOST" => "#{uri.host}:#{uri.port}",
        "CONTENT-LENGTH" => body.length.to_s,
        "CONTENT-TYPE" => 'text/xml; charset="utf-8"',
        "SOAPACTION" => %{"#{ns}##{method}"}
    }
    response = Net::HTTP.start( uri.host, uri.port ) do |http|
      http.post( uri.request_uri, body, headers )
    end
    if !response.is_a? Net::HTTPSuccess
      error = REXML::Document.new response.body
      error.elements.each( "//errorDescription" ) do |err|
        puts "UPnP warning: Failure for #{uri.host}: #{err.text}"
      end
      return nil
    end
    return response.body
  end
end
