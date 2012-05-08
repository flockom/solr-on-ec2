#! /usr/bin/env ruby

require 'json'

# TODO: support for single machine shard, i.e. no slaves no HAProxy

# USAGE: ./ec2-run-instances-blocking.rb CLUSTER 
#     CLUSTER    - file specifying the cluster
#     KEY        - AWS 502 key to use i.e -k arg to ec2-run-instances


# CLUSTER grammar where [X] is zero or more Xs and (a,b,c) is a tuple,
# capitol is non-terminal lowercase is a terminal which should be double-quoted
#
#  CLUSTER     -> [SHARD]
#  SHARD       -> (SOLR_MASTER,[SOLR_SLAVE],HAPROXY)
#  SOLR_MASTER -> (SERVER,port,directory)
#  SOLR_SLAVE  -> (SERVER,port,directory)
#  HAPROXY     -> (SERVER,port)
#  SERVER      -> (ec2_instance_id,ami,ec2_type,public_host,public_ip,private_host,private_ip)

#populates the server with the ec2_id, private/public ip/host
def update_server(server, ec2_info)
  server[0] = ec2_info[1] # ec2_id
  server[3] = ec2_info[3] # public host
  server[4] = ec2_info[16] # public ip
  server[5] = ec2_info[4] # private host
  server[6] = ec2_info[17] # private ip
end

# the input to this program takes a CLUSTER with ec2_instance_id's as
# unique integers for each machine, and the public/private host/ips
# blank it will determine how many of which type of instances with
# which ami should be allocated and then allocate them. It will then
# output the same grammar to stdout except the public/private
# host/ip's and ec2_instance_ids will be filled in with those from
# amazon.

# example input: 2x2 cluster with HAPROXY running on the masters
# [ 
#  [
#   [ ["0","ami-xxxx","m1.small","","","",""],"8081","/home/solrm"],
#   [[["1","ami-xxxx","m1.small","","","",""],"8082","/home/solrs"]],
#   [["0","ami-xxxx","m1.small","","","",""],"8080"]
#  ],
 
#  [
#   [ ["2","ami-xxxx","m1.small","","","",""],"8181","/home/solrm"],
#   [[["3","ami-xxxx","m1.small","","","",""],"8182","/home/solrs"]],
#   [["2","ami-xxxx","m1.small","","","",""],"8180"]
#  ]
# ]

f = File.open(ARGV[0])
cluster_s = f.read
cluster = JSON.parse(cluster_s)


# first make a hash of pseudo_id=>[ami,ec2_type] to get the number
instances = Hash.new

cluster.each do |shard|
  # get the SOLR_MASTER instance
  instances[shard[0][0][0]] = [shard[0][0][1],shard[0][0][2]]
  # get the HAPROXY instance
  instances[shard[2][0][0]] = [shard[2][0][1],shard[2][0][2]]
  # get each SOLR_SLAVE instance
   shard[1].each do |slave|
     instances[slave[0][0]] = [slave[0][1],slave[0][2]]
   end
end

# enumerate the first hash to make a second of [ami,ec2_type]=>count
# then we know how many of each ami,type to launch
tally = Hash.new
instances.each do |key,value|
  if(tally[value] == nil)
    tally[value] = 1
  else
    tally[value] = tally[value]+1
  end
end


# launch them and build an hash of [ami,ec2_type]=>[instance_output]
# where instance_output is the line output of ec2-run-instances as an array
# which contains all the information about that instance
r_instances = Hash.new
tally.each do |type,count|
  r_instances[type] = `./ec2-run-instances-blocking.rb #{type[0]} #{type[1]} #{count} #{ARGV[1]} | grep INSTANCE`.split("\n").map {|i| i.split("\t")}
end

# allocate launched instances to instances required then populate the
# cluster with the running instance information
instances.each do |key,value|
  inst = r_instances[value].pop
  #associate the pseudo id with the ec2 instance
  instances[key] = [value,inst]
end

# now iterate the cluster and add in the actual SERVER info
cluster.each do |shard|
  # update the SOLR_MASTER instance
  update_server(shard[0][0],instances[shard[0][0][0]][1])
  # update the HAPROXY instance
  update_server(shard[2][0],instances[shard[2][0][0]][1])
  # update each SOLR_SLAVE instance
   shard[1].each do |slave|
    update_server(slave[0],instances[slave[0][0]][1])
   end
end

#print out the cluster config populated with the server info
print cluster
