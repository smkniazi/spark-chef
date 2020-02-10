#
# Cookbook Name:: spark
# Recipe:: install
#
# Copyright 2015, Jim Dowling
#
# All rights reserved
#

include_recipe "java"

group node['hadoop_spark']['group'] do
  action :create
  not_if "getent group #{node['hadoop_spark']['group']}"
  not_if { node['install']['external_users'].casecmp("true") == 0 }
end

user node['hadoop_spark']['user'] do
  gid node['hadoop_spark']['group']
  action :create
  system true
  shell "/bin/false"
  not_if "getent passwd #{node['hadoop_spark']['user']}"
  not_if { node['install']['external_users'].casecmp("true") == 0 }
end

group node['hadoop_spark']['group'] do
  action :modify
  members ["#{node['hadoop_spark']['user']}"]
  append true
  not_if { node['install']['external_users'].casecmp("true") == 0 }
end

directory node['hadoop_spark']['dir']  do
  owner "root"
  group node['hadoop_spark']['group']
  mode "755"
  action :create
  not_if { File.directory?("#{node['hadoop_spark']['dir']}") }
end

package_url = "#{node['hadoop_spark']['url']}"
if node['install']['enterprise']['install'].casecmp? "true"
  package_url = "#{node['install']['enterprise']['download_url']}/spark/spark-#{node['hadoop_spark']['version']}-bin-without-hadoop-with-hive-with-r.tgz"
end

base_package_filename = File.basename(package_url)
cached_package_filename = "#{Chef::Config['file_cache_path']}/#{base_package_filename}"

remote_file cached_package_filename do
  source package_url
  owner "root"
  mode "0644"
  headers get_ee_basic_auth_header()
  sensitive true
  action :create_if_missing
end

package "zip" do
  action :install
end

spark_down = "#{node['hadoop_spark']['home']}/.hadoop_spark.extracted_#{node['hadoop_spark']['version']}"

# Extract Spark
bash 'extract_hadoop_spark' do
        user "root"
        code <<-EOH
                set -e
                rm -rf #{node['hadoop_spark']['base_dir']}
                tar -xf #{cached_package_filename} -C #{node['hadoop_spark']['dir']}
                chown -R #{node['hadoop_spark']['user']}:#{node['hadoop_spark']['group']} #{node['hadoop_spark']['dir']}/spark*
                chmod -R 755 #{node['hadoop_spark']['dir']}/spark*
                touch #{spark_down}
        EOH
     not_if { ::File.exists?( spark_down ) }
end

bash 'link_jars' do
        user "root"
        code <<-EOH
                set -e
                rm -f #{node['hadoop_spark']['home']}/python/lib/py4j-src.zip
                ln -s #{node['hadoop_spark']['home']}/python/lib/py4j-*-src.zip #{node['hadoop_spark']['home']}/python/lib/py4j-src.zip
                rm -f #{node['hadoop_spark']['home']}/jars/datanucleus-api-jdo.jar
                ln -s #{node['hadoop_spark']['home']}/jars/datanucleus-api-jdo-*.jar #{node['hadoop_spark']['home']}/jars/datanucleus-api-jdo.jar
                rm -f #{node['hadoop_spark']['home']}/jars/datanucleus-core.jar
                ln -s #{node['hadoop_spark']['home']}/jars/datanucleus-core-*.jar #{node['hadoop_spark']['home']}/jars/datanucleus-core.jar
                rm -f #{node['hadoop_spark']['home']}/jars/datanucleus-rdbms.jar
                ln -s #{node['hadoop_spark']['home']}/jars/datanucleus-rdbms-*.jar #{node['hadoop_spark']['home']}/jars/datanucleus-rdbms.jar
        EOH
end

link node['hadoop_spark']['base_dir'] do
  owner node['hadoop_spark']['user']
  group node['hadoop_spark']['group']
  to node['hadoop_spark']['home']
end

#Copy SQL dependencies to SPARK_HOME/jars
purl=node['hadoop_spark']['spark_sql_dependencies_url']
# The following dependencies are required to run spark-sql with parquet and orc. We install them here so that users don't have to do it from their notebooks/jobs
# https://mvnrepository.com/artifact/org.spark-project.hive/hive-exec/1.2.1.spark2
# http://central.maven.org/maven2/org/iq80/snappy/snappy/0.4/

# To make sure that all the custom jars that do not come with the Spark distribution are correctly updated
# during installation/upgrades, we create a separate directory which is cleaned up every time we run this recipe.
directory node['hadoop_spark']['hopsworks_jars'] do
  recursive true
  action :delete
  only_if { ::Dir.exist?(node['hadoop_spark']['hopsworks_jars']) }
end

directory node['hadoop_spark']['hopsworks_jars'] do
  owner node['hadoop_spark']['user']
  group node['hadoop_spark']['group']
  mode "0755"
  action :create
end

# We create a symlink from within spark/jars that points to spark/hopsworks-jars so that all the custom libraries 
# are transparently available to the spark applications without the need of fixing the classpaths.
link "#{node['hadoop_spark']['home']}/jars/hopsworks-jars" do
  to node['hadoop_spark']['hopsworks_jars']
  link_type :symbolic
end

sql_dep = [
  "parquet-encoding-#{node['hadoop_spark']['parquet_version']}.jar",
  "parquet-encoding-#{node['hadoop_spark']['parquet_version']}.jar",
  "parquet-common-#{node['hadoop_spark']['parquet_version']}.jar",
  "parquet-hadoop-#{node['hadoop_spark']['parquet_version']}.jar",
  "parquet-jackson-#{node['hadoop_spark']['parquet_version']}.jar",
  "parquet-column-#{node['hadoop_spark']['parquet_version']}.jar",
  "parquet-column-#{node['hadoop_spark']['parquet_version']}.jar",
  "parquet-column-#{node['hadoop_spark']['parquet_version']}.jar",
  "parquet-column-#{node['hadoop_spark']['parquet_version']}.jar",
  "parquet-format-#{node['hadoop_spark']['parquet_format_version']}.jar",
  "snappy-0.4.jar",
  "spark-avro_#{node['hadoop_spark']['spark_avro_version']}.jar",
  "spark-tensorflow-connector_#{node['hadoop_spark']['tf_spark_connector_version']}.jar",
  "spark-avro_#{node['hadoop_spark']['databricks_spark_avro_version']}.jar",
  "delta-core_#{node['hadoop_spark']['databricks_delta_version']}.jar"
]
for f in sql_dep do
  remote_file "#{node['hadoop_spark']['hopsworks_jars']}/#{f}" do
    source "#{purl}/#{f}"
    owner node['hadoop_spark']['user']
    group node['hadoop_spark']['group']
    mode "0644"
    action :create_if_missing
  end
end

hudi_bundle =File.basename(node['hadoop_spark']['hudi_bundle_url'])
remote_file "#{node['hadoop_spark']['hopsworks_jars']}/#{hudi_bundle}" do
  source node['hadoop_spark']['hudi_bundle_url']
  owner node['hadoop_spark']['user']
  group node['hops']['group']
  mode "0644"
  action :create
end

# Download MySQL Driver for Online featurestore
mysql_driver=File.basename(node['hadoop_spark']['mysql_driver'])
remote_file "#{node['hadoop_spark']['hopsworks_jars']}/#{mysql_driver}" do
  source node['hadoop_spark']['mysql_driver']
  owner node['hadoop_spark']['user']
  group node['hadoop_spark']['group']
  mode "0644"
  action :create_if_missing
end

hopsUtil=File.basename(node['hadoop_spark']['hopsutil']['url'])
remote_file "#{node['hadoop_spark']['hopsworks_jars']}/#{hopsUtil}" do
  source node['hadoop_spark']['hopsutil']['url']
  owner node['hadoop_spark']['user']
  group node['hops']['group']
  mode "0644"
  action :create
end

elastic_connector=File.basename(node['hadoop_spark']['elastic_connector']['url'])
remote_file "#{node['hadoop_spark']['hopsworks_jars']}/#{elastic_connector}" do
  source node['hadoop_spark']['elastic_connector']['url']
  owner node['hadoop_spark']['user']
  group node['hops']['group']
  mode "0644"
  action :create
end

template"#{node['hadoop_spark']['conf_dir']}/log4j.properties" do
  source "app.log4j.properties.erb"
  owner node['hadoop_spark']['user']
  group node['hadoop_spark']['group']
  mode 0650
end

template"#{node['hadoop_spark']['conf_dir']}/yarnclient-driver-log4j.properties" do
  source "yarnclient-driver-log4j.properties.erb"
  owner node['hadoop_spark']['user']
  group node['hadoop_spark']['group']
  mode 0655
end

template"#{node['hadoop_spark']['conf_dir']}/executor-log4j.properties" do
  source "executor-log4j.properties.erb"
  owner node['hadoop_spark']['user']
  group node['hadoop_spark']['group']
  mode 0655
end


my_ip = my_private_ip()

master_ip = "yarn"

begin
  namenode_ip = private_recipe_ip("hops","nn")
rescue
  begin
    namenode_ip = private_recipe_ip("hops","nn")
  rescue
    namenode_ip = my_private_ip()
  end
end

template"#{node['hadoop_spark']['home']}/conf/spark-env.sh" do
  source "spark-env.sh.erb"
  owner node['hadoop_spark']['user']
  group node['hadoop_spark']['group']
  mode 0655
  variables({
        :master_ip => master_ip,
        :private_ip => my_ip
           })
end


eventlog_dir = "#{node['hops']['hdfs']['user_home']}/#{node['hadoop_spark']['user']}/applicationHistory"

begin
  historyserver_ip = private_recipe_ip("hadoop_spark","historyserver")
rescue
  historyserver_ip = my_private_ip()
end

template"#{node['hadoop_spark']['home']}/conf/spark-defaults.conf" do
  source "spark-defaults.conf.erb"
  owner node['hadoop_spark']['user']
  group node['hadoop_spark']['group']
  mode 0655
  variables({
        :private_ip => my_ip,
        :master_ip => master_ip,
        :namenode_ip => namenode_ip,
        :yarn => node['hadoop_spark']['yarn']['support'],
        :eventlog_dir => eventlog_dir,
        :historyserver_ip => historyserver_ip
           })
end

template"#{node['hadoop_spark']['home']}/conf/spark-blacklisted-properties.txt" do
  source "spark-blacklisted-properties.txt.erb"
  owner node['hadoop_spark']['user']
  group node['hadoop_spark']['group']
  mode 0655
end

magic_shell_environment 'SPARK_HOME' do
  value node['hadoop_spark']['base_dir']
end

nn_endpoint = private_recipe_ip("hops", "nn") + ":#{node['hops']['nn']['port']}"
begin
  metastore_ip = private_recipe_ip("hive2", "metastore")
rescue
  metastore_ip = private_recipe_ip("hive2", "default")
  Chef::Log.warn "Using default ip for metastore (metastore service not defined in cluster definition (yml) file."
end

template "#{node['hadoop_spark']['home']}/conf/hive-site.xml" do
  source "hive-site.xml.erb"
  owner node['hadoop_spark']['user']
  group node['hadoop_spark']['group']
  mode 0655
  variables({
                :nn_endpoint => nn_endpoint,
                :metastore_ip => metastore_ip
            })
end
