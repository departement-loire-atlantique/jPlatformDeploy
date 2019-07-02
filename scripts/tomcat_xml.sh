# This scripts manage tomcat.xml updates for JCMS 10

# STEP 1 - Add BDD POOL RESOURCE

# https://collaboratif.loire-atlantique.fr/share/page/site/ExploitationSI/wiki-page?title=Tomcat_tcServer_-_Base_de_connaissances#Pools_JDBC___Configuration

if [[ ! -v TOMCAT_DIR ]]; then
    echo "TOMCAT_DIR is not set"
    exit 1

if [[ ! -v JDBC_PATH ]]; then
    echo "JDBC_PATH is not set"
    exit 1

if [[ ! -v JDBC_PASSWORD ]]; then
    echo "JDBC_PATH is not set"
    exit 1

if [[ ! -f "$TOMCAT_DIR/conf/tomcat.xml" ]]; then
    echo "$TOMCAT_DIR/conf/tomcat.xml does not exists"
    exit 1

POOL_XML=" 
<Resource auth="Container"
  defaultAutoCommit="false"
  defaultReadOnly="false"
  defaultTransactionIsolation="READ_COMMITTED"
  driverClassName="org.postgresql.Driver"
  factory="org.apache.tomcat.jdbc.pool.DataSourceFactory"
  fairQueue="false"
  initialSize="10"
  jdbcInterceptors="ConnectionState;StatementFinalizer"
  jmxEnabled="true"
  logAbandoned="false"
  maxActive="100"
  maxIdle="100"
  maxWait="10000"
  minEvictableIdleTimeMillis="10000"
  minIdle="10"
  name="jdbc/JcmsPool"
  password="$JDBC_PASSWORD"
  removeAbandoned="false"
  removeAbandonedTimeout="60"
  testOnBorrow="true"
  testOnReturn="false"
  testWhileIdle="false"
  timeBetweenEvictionRunsMillis="10000"
  type="javax.sql.DataSource"
  url="$JDBC_PATH"
  useEquals="false"
  username="gstsii"
  validationInterval="30000"
validationQuery="select version()"/>
"

if cat $TOMCAT_DIR/conf/tomcat.xml | grep <Resource auth="Container" > 0; then
   sed -i -e '/<Resource auth="Container".*</Ressource>/' $TOMCAT_DIR/conf/tomcat.xml

sed -i -e '/<GlobalNamingResources>/<GlobalNamingResources>POOL_XML' $TOMCAT_DIR/conf/tomcat.xml
