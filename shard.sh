#!/bin/bash
tar -xf mongodb-linux-x86_64-rhel70-5.0.6.tgz 
cp -r  mongodb-linux-x86_64-rhel70-5.0.6/ /mongodb/
useradd -r mongod -s /sbin/nologin
chown -R mongod:mongod /mongodb/
echo 'export PATH=/mongodb/bin:$PATH' >> /etc/profile
source /etc/profile &> /dev/null

# shard1 conf
# 一主两从，其中一个节点为arbiter，复制集名字repo1
for port in {27017,27018,27019}
do
mkdir -pv /mongodb/${port}/{db,log,conf}
cat > /mongodb/${port}/conf/mongodb.conf << EOF
# 系统日志相关
systemLog:
  destination: file
  # 日志位置
  path: /mongodb/${port}/log/mongodb.log
  # 日志以追加的模式记录
  logAppend: true
# 数据存储有关
storage:
  journal:
    enabled: true
  # 数据路径位置
  dbPath: /mongodb/${port}/db
  directoryPerDB: true
  wiredTiger:
    engineConfig:
      cacheSizeGB: 1
      directoryForIndexes: true
    collectionConfig:
      blockCompressor: zlib
    indexConfig:
      prefixCompression: true
# 网络配置有关
net:
  # 监听地址
  bindIp: 192.168.174.10,127.0.0.1
  # 默认端口号
  port: ${port}
replication:
  oplogSizeMB: 2048
  # 副本集名
  replSetName: repl1
  
sharding:
  clusterRole: shardsvr
# 进程控制
processManagement: 
  # 后台守护进程
  fork: true
  pidFilePath: /mongodb/${port}/log/mongod.pid
EOF
chown -R mongod:mongod /mongodb/
mongod -f /mongodb/${port}/conf/mongodb.conf
done
mongo 127.0.0.1:27017/admin --eval "rs.initiate({_id: 'repl1', members: [ {_id: 0, host: '192.168.174.10:27017'}, {_id: 1, host: '192.168.174.10:27018'}, {_id: 2, host: '192.168.174.10:27019',"arbiterOnly":true}] })"

# shard2 conf
# 一主两从，其中一个节点为arbiter，复制集名字repo2
for port in {37017,37018,37019}
do
mkdir -pv /mongodb/${port}/{db,log,conf}
chown -R mongod:mongod /mongodb/${port}
cat > /mongodb/$port/conf/mongodb.conf << EOF
systemLog:
  destination: file
  path: /mongodb/${port}/log/mongodb.log   
  logAppend: true
storage:
  journal:
    enabled: true
  dbPath: /mongodb/${port}/db
  directoryPerDB: true
  wiredTiger:
    engineConfig:
      cacheSizeGB: 1
      directoryForIndexes: true
    collectionConfig:
      blockCompressor: zlib
    indexConfig:
      prefixCompression: true
net:
  bindIp: 192.168.174.10,127.0.0.1
  port: ${port}
replication:
  oplogSizeMB: 2048
  replSetName: repl2
sharding:
  clusterRole: shardsvr
processManagement: 
  fork: true
  pidFilePath: /mongodb/${port}/log/mongod.pid
EOF
mongod -f /mongodb/${port}/conf/mongodb.conf
done
mongo 127.0.0.1:37017/admin --eval "rs.initiate({_id: 'repl2', members: [ {_id: 0, host: '192.168.174.10:37017'}, {_id: 1, host: '192.168.174.10:37018'}, {_id: 2, host: '192.168.174.10:37019',"arbiterOnly":true}] })"

# config Server不支持arbiter
# config Server conf
for port in {47017,47018,47019}
do
mkdir -pv /mongodb/${port}/{db,log,conf}
chown -R mongod:mongod /mongodb/${port}
cat > /mongodb/${port}/conf/mongodb.conf <<EOF
systemLog:
  destination: file
  path: /mongodb/${port}/log/mongodb.log
  logAppend: true
storage:
  journal:
    enabled: true
  dbPath: /mongodb/${port}/db
  directoryPerDB: true
  #engine: wiredTiger
  wiredTiger:
    engineConfig:
      cacheSizeGB: 1
      directoryForIndexes: true
    collectionConfig:
      blockCompressor: zlib
    indexConfig:
      prefixCompression: true
net:
  bindIp: 192.168.174.10,127.0.0.1
  port: $port
replication:
  oplogSizeMB: 2048
  replSetName: configReplSet
sharding:
  clusterRole: configsvr
processManagement: 
  fork: true
  pidFilePath: /mongodb/${port}/log/mongod.pid
EOF
mongod -f /mongodb/$port/conf/mongodb.conf
done
mongo 127.0.0.1:47017/admin --eval "rs.initiate({_id: 'configReplSet', members: [ {_id: 0, host: '192.168.174.10:47017'}, {_id: 1, host: '192.168.174.10:47018'}, {_id: 2, host: '192.168.174.10:47019'}] })"

# mongos nodes
port=57017
mkdir -pv /mongodb/${port}/{log,conf}
chown -R mongod:mongod /mongodb/${port}
cat > /mongodb/$port/conf/mongodb.conf << EOF
systemLog:
  destination: file
  path: /mongodb/$port/conf/mongodb.conf
  logAppend: true
net:
  bindIp: 192.168.174.10,127.0.0.1
  port: $port
sharding:
  configDB: configReplSet/192.168.174.10:47017,192.168.174.10:47018,192.168.174.10:47019
processManagement: 
  fork: true
  pidFilePath: /mongodb/${port}/log/mongod.pid
EOF

mongos -f /mongodb/$port/conf/mongodb.conf

# 添加分片
mongo 127.0.0.1:57017/admin --eval "db.runCommand( { addshard : 'repl1/192.168.174.10:27017,192.168.174.10:27018,192.168.174.10:27019',name:'shard1'} )"
mongo 127.0.0.1:57017/admin --eval "db.runCommand( { addshard : 'repl2/192.168.174.10:37017,192.168.174.10:37018,192.168.174.10:37019',name:'shard2'} )"

# 列出分片
mongo 127.0.0.1:57017/admin --eval "db.runCommand( { listshards : 1 } )"
