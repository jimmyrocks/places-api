dbname=osm_de_api
dbfile=delaware-latest.osm.pbf
dbfileUrl=http://download.geofabrik.de/north-america/us/$dbfile
user=osm
pass=osm
home_dir=`echo ~`
this_dir=`pwd`

# Set up the OSM user and the DB
sudo -u postgres psql -c "CREATE USER $user WITH PASSWORD '$pass'"
sudo -u postgres psql -c "ALTER USER osm WITH SUPERUSER;"
sudo -u postgres dropdb $dbname
sudo -u postgres createdb -E UTF8 $dbname
sudo -u postgres createlang -d $dbname plpgsql

# Create the database extentions
sudo -u postgres psql -d $dbname -c "CREATE EXTENSION hstore;"

# Run the structure file
sudo -u postgres psql -d $dbname -f $home_dir/installation/db/sql/structure.sql

# Download the extract
mkdir -p $home_dir/installation/extracts
cd $home_dir/installation/extracts
wget $dbfileUrl

# Load the file into the database
$home_dir/installation/osmosis/bin/osmosis --read-pbf file="$home_dir/installation/extracts/$dbfile" --write-apidb  database="$dbname" user="$user" password="$pass" validateSchemaVersion=no

# Update the sequences and functions
sudo -u postgres psql -d $dbname -f $this_dir/poi-api-functions.sql

cd $this_dir
exit
