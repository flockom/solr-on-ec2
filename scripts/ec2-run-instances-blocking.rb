#! /usr/bin/env ruby


# essential the same as ec2-run-instances except this will block until
# all the instances are available.


# TODO: should make it take the same parameters as ec2-run-instances i.e. just pass them all along       

# USAGE: ./ec2-run-instances-blocking.rb AMI TYPE NUMBER KEY
#     AMI    - the amazon machine image number to launch ex 'ami-4dad7424'
#     TYPE   - instance type to launc ex 't1.micro' (--instance-type)
#     NUMBER - how many to launch (-n)
#     KEY    - 502 key to use (-k)


#launch them with ec2-run-instances , get the ids

output = `ec2-run-instances #{ARGV[0]} --instance-type #{ARGV[1]} -n #{ARGV[2]} -k #{ARGV[3]} | grep INSTANCE`

#print "ec2-run-instances #{ARGV[0]} --instance-type #{ARGV[1]} -n #{ARGV[2]} -k #{ARGV[3]} | grep INSTANCE"

output = output.split("\n").map {|i| i.split("\t")}

#output[x][1] - instance id
#output[x][5] - instance status
#output[x][3] - public host
#output[x][4] - private host
#output[x][16] - public ip
#output[x][17] - private ip

#instance ids
ids = output.map {|i| i[1]}
flatIds = ids.reduce("") {|ids,id| ids+id+" "}

# wait until all instances are running
begin
statuss = `ec2-describe-instances #{flatIds} | grep INSTANCE`
status  = statuss.split("\n").map {|i| i.split("\t")}
end while !status.reduce(true) {|all,one| all && one[5]=="running"}

# normal ec2-run-instances(without reservation) output but they will all be running
print statuss



