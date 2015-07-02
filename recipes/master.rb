
spark_start "master" do
  action :start_master
end

hadoop_hdfs_directory "/user/#{node[:spark][:user]}/share/lib" do 
  action :create_as_superuser
  owner node[:spark][:user]
  group node[:spark][:group]
  mode "755"
end

#hadoop_hdfs_directory "#{node[:spark][:home]}/assembly/lib/spark-assembly_*.jar" do
#  action :put
#  dest "/user/#{node[:spark][:user]}/share/lib/spark-assembly.jar "
#  owner node[:spark][:user]
#  mode "0755"
#end

# hdfs dfs -mkdir -p /user/spark/share/lib 
# hdfs dfs -put $SPARK_HOME/assembly/lib/spark-assembly_*.jar  \     
# /user/spark/share/lib/spark-assembly.jar 
# SPARK_JAR=hdfs://<nn>:<port>/user/spark/share/lib/spark-assembly.jar

template"#{node[:spark][:home]}/conf/slaves" do
  source "slaves.erb"
  owner node[:spark][:user]
  group node[:spark][:group]
  mode 0655
end

