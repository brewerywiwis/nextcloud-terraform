terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 3.27"
    }
  }
  required_version = ">= 0.14.9"
}

provider "aws" {
  profile = "default"
  region  = var.region
}

resource "aws_key_pair" "generated_key" {
  key_name   = "ssh-key"
  public_key = var.ssh_public_key
}
resource "aws_instance" "db_server" {
  ami           = var.ami
  instance_type = "t2.micro"
  key_name      = aws_key_pair.generated_key.key_name
  network_interface {
    network_interface_id = aws_network_interface.nat-db-nic.id
    device_index         = 0
  }
  network_interface {
    network_interface_id = aws_network_interface.local-db-nic.id
    device_index         = 1
  }
  user_data = <<-EOF
                #!/bin/bash
                sudo apt update
                sudo apt install -y mariadb-server
                sudo mysql -e "SET PASSWORD FOR ${var.database_user}@localhost = PASSWORD('${var.database_pass}');UPDATE mysql.user SET HOST='%' WHERE User='${var.database_user}';FLUSH PRIVILEGES;"
                sudo sed -i "s/.*bind-address.*/bind-address = 0.0.0.0/" /etc/mysql/mariadb.conf.d/50-server.cnf
                sudo service mariadb restart
              EOF
  tags = {
    Name = "nextcloud-db"
  }
}

resource "aws_instance" "app_server" {
  depends_on = [
    aws_instance.db_server,
    aws_iam_access_key.s3-access-key
  ]
  ami           = var.ami
  instance_type = "t2.micro"

  network_interface {
    network_interface_id = aws_network_interface.app-public-nic.id
    device_index         = 0
  }
  network_interface {
    network_interface_id = aws_network_interface.local-app-nic.id
    device_index         = 1
  }

  user_data = <<-EOF
              #!/bin/bash
              sudo apt update
              sudo apt install -y php libapache2-mod-php wget unzip
              sudo systemctl restart apache2

              sudo apt install -y \
                  php-fpm \
                  php-intl \
                  php-ldap \
                  php-imap \
                  php-gd \
                  php-mysql\
                  php-curl \
                  php-xml \
                  php-zip \
                  php-mbstring \
                  php-soap \
                  php-json \
                  php-gmp \
                  php-bz2 \
                  php-bcmath \
                  php-pear

              echo '<IfModule mod_dir.c>
              	DirectoryIndex index.php index.html index.cgi index.pl index.xhtml index.htm
              </IfModule>' > /etc/apache2/mods-enabled/dir.conf

              echo 'Alias /nextcloud "/var/www/nextcloud/"
                    <Directory /var/www/nextcloud/>
                      Require all granted
                      AllowOverride All
                      Options FollowSymLinks MultiViews

                      <IfModule mod_dav.c>
                        Dav off
                      </IfModule>
                    </Directory>' > /etc/apache2/sites-available/nextcloud.conf

              wget https://download.nextcloud.com/server/releases/nextcloud-22.2.3.zip -O /tmp/nextcloud.zip
              unzip /tmp/nextcloud.zip -d /var/www/
              #sudo rm -r /tmp/nextcloud*

              a2ensite nextcloud.conf
              a2enmod rewrite
              a2enmod headers
              a2enmod env
              a2enmod dir
              a2enmod mime
              service apache2 restart

              sudo chown -R www-data:www-data /var/www/nextcloud/

              cd /var/www/nextcloud/

              while true; do
                if telnet 172.16.2.200 3306 | grep -q "Escape character is '^]'."; then
                    echo "DB connect SUCCESS"
                    break
                else
                    echo "DB connect FAILED"
                fi
                sleep 2
              done

              sudo -u www-data php occ  maintenance:install \
              --database "mysql" --database-host "172.16.2.200" --database-name "${var.database_name}" \
              --database-user "${var.database_user}" --database-pass "${var.database_pass}" \
              --admin-user "${var.admin_user}" --admin-pass "${var.admin_pass}"

              sudo -u www-data php occ config:system:set trusted_domains 1 --value=*

              sudo -u www-data php occ config:system:delete objectstore
              sudo -u www-data php occ config:system:set objectstore class --value='\OC\Files\ObjectStore\S3'
              sudo -u www-data php occ config:system:set objectstore arguments bucket --value='${var.bucket_name}'
              sudo -u www-data php occ config:system:set objectstore arguments autocreate --value=true
              sudo -u www-data php occ config:system:set objectstore arguments key --value='${aws_iam_access_key.s3-access-key.id}'
              sudo -u www-data php occ config:system:set objectstore arguments secret --value='${aws_iam_access_key.s3-access-key.secret}'
              sudo -u www-data php occ config:system:set objectstore arguments use_ssl --value=true
              sudo -u www-data php occ config:system:set objectstore arguments region --value='${var.region}'

              sudo echo "SUCCESS" > /tmp/success
              EOF

  tags = {
    Name = "nextcloud-app"
  }
}
