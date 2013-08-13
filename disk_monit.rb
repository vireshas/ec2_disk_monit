require "net/ssh"
require "AWS"
require "timeout"

class EC2Helpers

  def initialize(disk_limit, key, secret, mail)
    @filter = disk_limit
    @access_key = key
    @secret_key = secret
    @email = mail
  end

  def get_disk_info_of(servers)
    @file = File.open("mail.html","w")
    servers.each do |server|
      puts server;
      begin
        Timeout::timeout(5){
          ssh_and_get_disk_info_for(server, 'df -h|grep "sda\|ebs\|xvd"')
        }
      rescue
        ssh_and_get_disk_info_for(server, 'ps aux | grep df | awk "{print $2}" | xargs kill')
      end
    end
    `sudo mail -a "Content-type: text/html;" -s "disk_info" #{@email} < mail.html`
  end

  def ssh_and_get_disk_info_for(instance, command)
    begin
      Net::SSH.start(instance, 'ubuntu',
                     :keys => '/home/ubuntu/.ssh/id_rsa',
                     :paranoid => false,
                     :timeout => 20,
                     :user_known_hosts_file => '/dev/null') do |ssh|
        if command['kill']
          puts "killing df -h"
          @file.puts "<h4><font color='red'>#{instance}, \"#{@tag_names[instance]}\"</font></h4>"
          @file.puts "couldn't complete 'df -h' in 5s"
        else
          df = ssh.exec!(command)
          @file.puts "<h4>#{instance}, \"#{@tag_names[instance]}\"</h4>"
          dfs =  df.split("\n")
          dfs.each do |d|
            percentage = d.split(" ")[-2].to_i
            d = d.gsub(" ","&nbsp;")
            @file.puts (percentage > FILTER ? "<b><font color='red'>#{d}</font></b><br>" : "#{d}<br>")
          end
        end
        @file.puts "<hr>"
        @file.flush
      end
    rescue Net::SSH::AuthenticationFailed
      return
    end
  end

  def app_servers
    @app_servers ||= ec2
  end

  def ec2(filter = "")
    @ec2 ||= AWS::EC2::Base.new(:access_key_id => @access_key , :secret_access_key => @secret_key )
    all_instances = []
    @tag_names = {}
    all_instance_sets.each do |instance_set|
      instances(instance_set).each do |instance|
        all_instances << ec2_name(instance)
        @tag_names[ec2_name(instance)] = tag_name_of(instance)
      end
    end
    all_instances.compact
  end

  def tag_name_of(instance)
    instance["tagSet"] ? instance["tagSet"]["item"].first["value"] : "spot"
  end

  def all_instance_sets
    @all_instance_sets ||=  @ec2.describe_instances['reservationSet']['item']
    @all_instance_sets
  end

  def instances(instance_set)
    instance_set['instancesSet']['item']
  end

  def ec2_name(instance)
    instance['dnsName']
  end

  def filter?(instance, filter)
    matched = false
    tags = instance['tagSet']
    tags && tags['item'].each do |tag|
      matched = true if tag['key'] == "Name" && tag['value'].match(filter)
    end
    matched
  end
end
