#! /usr/bin/env ruby

require 'json'

# This takes a CLUSTER specification which has been run through
# ec2-run-cluster.rb to boot the instances and starts the Solr and
# HAProxy servicies on the machines so the cluster is ready to index
# documents.

# TODO: maybe a flag to specify if master should be added to the shards HAPROXY_CONF
#       support for single machine shard, i.e. no slaves no HAProxy

# USAGE: ./ec2-config-solr-cluster.rb CLUSTER KEY ID SOLR_MASTER_CONF SOLR_SLAVE_CONF SCHEMA
#     CLUSTER          - file specifying the cluster w/ ips (output of ec2-run-cluster.rb)
#     KEY              - AWS 502 key to use i.e -k arg to ec2-run-instances
#     ID               - identitiy file (private key) to use for ssh i.e. "~/.ec2/id_rsa"
#     SOLR_MASTER_CONF - to be used as (from solr example)/solr/conf/solrconfig.xml on masters
#     SOLR_SLAVE_CONF  - to be used as (from solr example)/solr/conf/solrconfig.xml on slaves
#     SCHEMA           - schema.xml describing the documents to be indexed

                         
# user to log in as
USER         = "ubuntu"
# ssh options, first two stop ssh from asking for host verification
OPTS = "-o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -i #{ARGV[2]}"

# generates an HAProxy config
#
# name - some name to identify the shard
# ip      - ip that HAProxy should listen on (ec2 private ip for shards)
# port    - port HAProxy should listen on
# servers - array of SOLR_MASTER or SOLR_SLAVEs as specified in "ec2-run-cluster.rb"
#           please excuse my disregard for abstraction
def gen_HAProxy_config(name,port,servers)
   config = <<END
defaults
       option httpclose
       timeout connect 5000ms
       timeout client 50000ms
       timeout server 50000ms
	

listen #{name} 0.0.0.0:#{port}
       stats enable
       stats uri /haproxy?stats-#{name}
       mode http
       balance roundrobin
END
  
  #add servers to the end ex.
  #server shard-1-s1 localhost:8081 check
  servers.each_with_index do |server,i|
    config += "       server #{name}-#{i} #{server[0][6]}:#{server[1]} check\n"
  end
  return config
end


# load up the CLUSTER spec
f = File.open(ARGV[0])
cluster_s = f.read
cluster = JSON.parse(cluster_s)

# build the shards string pointing to each HAProxy service
# using the private ip
# TODO: if there is no proxy point to master
#       load up schema.xml into SOLR
shards = ""
cluster.each_with_index do |shard,i|
  shards += "#{shard[2][0][6]}:#{shard[2][1]}/solr" #HAProxy private IP
  if(i != cluster.size-1)    
    shards += ","
  end
end

#for each shard
cluster.each_with_index do |shard,i|
  puts "~+~+~+~+~+~+~+~+~+~+~+SHARD-#{i}~+~+~+~+~+~+~+~+~+~+~+"
  # the master
  puts "~+~+~+~+~+~+~+~+~+~+~+SHARD-#{i}-MASTER~+~+~+~+~+~+~+~+~+~+~+"
  # extract solr (should have done this in the ami)
  cmd = "ssh #{OPTS} #{USER}@#{shard[0][0][3]} 'sudo chown ubuntu:ubuntu /mnt; tar -xvf /home/ubuntu/apache-solr-3.6.0.tgz -C /mnt'"
  puts cmd;puts
  `#{cmd}`
  # make a copy of the solr example, so we can run multiple instances on one machine
  cmd = "ssh #{OPTS} #{USER}@#{shard[0][0][3]} 'cp -r /mnt/apache-solr-3.6.0/example /mnt/shard-#{i}-master'"
  puts cmd;puts
  `#{cmd}`
  # scp the SOLR_MASTER_CONF to the server
  cmd = "scp #{OPTS} #{ARGV[3]} #{USER}@#{shard[0][0][3]}:/mnt/shard-#{i}-master/solr/conf/solrconfig.xml"
  puts cmd;puts
  `#{cmd}`
  # scp the SCHEMA to the server
  cmd = "scp #{OPTS} #{ARGV[5]} #{USER}@#{shard[0][0][3]}:/mnt/shard-#{i}-master/solr/conf/schema.xml"
  puts cmd;puts
  `#{cmd}`
  # ssh in and start solr
  # replace this master's shard with itself in the shards list (avoid extra proxy lookup)
  shards_here = shards.sub(/#{shard[2][0][6]}:#{shard[2][1]}/,"127.0.0.1:#{shard[0][1]}")
  # start solr
  cmdd = "nohup java -Dsolr.distribution.shards=\"#{shards_here}\" -Djetty.port=#{shard[0][1]} -Dsolr.install=/mnt/apache-solr-3.6.0 -jar start.jar >/dev/null 2>/dev/null &"
  cmd = "ssh #{OPTS} #{USER}@#{shard[0][0][3]} 'PATH=$PATH:/opt/java6/bin; cd /mnt/shard-#{i}-master; #{cmdd} '"
  puts cmd;puts
  `#{cmd}`
  
  

  # each slave
  shard[1].each_with_index do |slave,ii|
    puts "~+~+~+~+~+~+~+~+~+~+~+SHARD-#{i}-SLAVE-#{ii}~+~+~+~+~+~+~+~+~+~+~+"
    # extract solr (should have done this in the ami)
    cmd = "ssh #{OPTS} #{USER}@#{slave[0][3]} 'sudo chown ubuntu:ubuntu /mnt; tar -xvf /home/ubuntu/apache-solr-3.6.0.tgz -C /mnt'"
    puts cmd;puts
    `#{cmd}`
    # make a copy of the solr example, so we can run multiple instances on one machine
    cmd = "ssh #{OPTS} #{USER}@#{slave[0][3]} 'cp -r /mnt/apache-solr-3.6.0/example /mnt/shard-#{i}-slave-#{ii}'"
    puts cmd;puts
    `#{cmd}`
    # scp the SOLR_MASTER_CONF to the server
    cmd = "scp #{OPTS} #{ARGV[4]} #{USER}@#{slave[0][3]}:/mnt/shard-#{i}-slave-#{ii}/solr/conf/solrconfig.xml"
    puts cmd;puts
    `#{cmd}`
    # scp the SCHEMA to the server
    cmd = "scp #{OPTS} #{ARGV[5]} #{USER}@#{slave[0][3]}:/mnt/shard-#{i}-master/solr/conf/schema.xml"
    puts cmd;puts
    `#{cmd}`
    # ssh in and start solr
    cmdd = "nohup java -Dsolr.replication.master=\"#{shard[0][0][5]}:#{shard[0][1]}\" -Dsolr.distribution.shards=\"#{shards}\" -Djetty.port=#{slave[1]} -Dsolr.install=/mnt/apache-solr-3.6.0 -jar start.jar >/dev/null 2>/dev/null &"
    cmd = "ssh #{OPTS} #{USER}@#{slave[0][3]} 'PATH=$PATH:/opt/java6/bin; cd /mnt/shard-#{i}-slave-#{ii}; #{cmdd}'"
    puts cmd;puts
    `#{cmd}`
  end
  
  puts "~+~+~+~+~+~+~+~+~+~+~+SHARD-#{i}-HAPROXY~+~+~+~+~+~+~+~+~+~+~+"
  # the HAProxy  
  # generate the config file
  haconfig = gen_HAProxy_config("shard-#{i}",shard[2][1],shard[1]+[shard[0]])
  puts haconfig
  # save it on the server
  File.open("./haproxy-tmp", 'w') {|f| f.write(haconfig)}
  cmd = "scp #{OPTS} ./haproxy-tmp #{USER}@#{shard[2][0][3]}:/mnt/shard-#{i}-haproxy"
  puts cmd;puts
  `#{cmd}`
  # launch haproxy on the server
  cmd = "ssh #{OPTS} #{USER}@#{shard[2][0][3]} 'nohup haproxy -f /mnt/shard-#{i}-haproxy >/dev/null 2>/dev/null &'"
  puts cmd;puts
  `#{cmd}`

end
