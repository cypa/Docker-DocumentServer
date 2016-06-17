FROM ubuntu:14.04
MAINTAINER Andrej Surkov <surae@yandex.ru> Ascensio System SIA <support@onlyoffice.com>

ENV LANG en_US.UTF-8  
ENV LANGUAGE en_US:en  
ENV LC_ALL en_US.UTF-8 

RUN DEBIAN_FRONTEND=noninteractive  
RUN apt-get update && \
    apt-get -y -q install libreoffice 
RUN echo "deb http://download.onlyoffice.com/repo/debian squeeze main" >>  /etc/apt/sources.list && \
    apt-key adv --keyserver keyserver.ubuntu.com --recv-keys D9D0BF019CC8AC0D
RUN echo "deb http://download.mono-project.com/repo/debian wheezy/snapshots/3.12.0  main" | sudo tee /etc/apt/sources.list.d/mono-xamarin.list && \
    apt-key adv --keyserver keyserver.ubuntu.com --recv-keys 3FA7E0328081BFF6A14DA29AA6A19B38D3D831EF
RUN echo "deb http://archive.ubuntu.com/ubuntu precise main universe multiverse" >> /etc/apt/sources.list && \
    locale-gen en_US.UTF-8 && \
    apt-get -y update
RUN echo ttf-mscorefonts-installer msttcorefonts/accepted-mscorefonts-eula select true | debconf-set-selections 
RUN apt-get install --force-yes -yq software-properties-common 
RUN add-apt-repository ppa:ubuntu-toolchain-r/test && \
    apt-get -y update && \
    apt-get --force-yes -yq install gcc-4.9 nano htop supervisor

# disable postinst
RUN apt-get download onlyoffice-documentserver && \
    dpkg --unpack onlyoffice-documentserver*.deb && \
    mv /var/lib/dpkg/info/onlyoffice-documentserver.postinst /root/ && \
    apt-get install -yf && \
    rm -rf /var/lib/apt/lists/*
RUN sed -ie '/\[supervisord\]/a nodaemon=true' /etc/supervisor/supervisord.conf  

# refactor deb postinst
ENV DIR="/var/www/onlyoffice"
ENV LOG_DIR="/var/log/onlyoffice"
ENV APP_DIR="/var/lib/onlyoffice"
ENV DB_HOST="127.0.0.1"
ENV DB_NAME="onlyoffice"
ENV DB_USER="root"
ENV DB_PWD=""

RUN adduser --quiet --home "$DIR" --system --group onlyoffice && \
    adduser --quiet www-data onlyoffice
RUN sed -e 's/-- CREATE/CREATE/;s/-- USE/USE/' /var/www/onlyoffice/documentserver/Schema/MySql.CreateDb.sql | grep -v -e '^[[:space:]]*$' | grep --invert-match -- -- | /usr/sbin/mysqld --bootstrap --user=root --skip-grant-tables
ENV CONN_STRING="Server=$DB_HOST;Database=$DB_NAME;User ID=$DB_USER;Password=$DB_PWD;Pooling=true;Character Set=utf8;AutoEnlist=false"
RUN sed -i "s/connectionString=.*/connectionString=\"$CONN_STRING\" providerName=\"MySql.Data.MySqlClient\"\/>/" "$DIR/documentserver/FileConverterService/Bin/ConnectionStrings.config" && \
    sed -i "s/connectionString=.*/connectionString=\"$CONN_STRING\" providerName=\"MySql.Data.MySqlClient\"\/>/" "$DIR/documentserver/DocService/ConnectionStrings.config" && \
    sed -i -r "s/\"host\"[[:blank:]]*:[[:blank:]]*\"[[:alnum:].:]+\"/\"host\": \"$DB_HOST\"/" "$DIR/documentserver/CoAuthoringService/CoAuthoring/sources/config.json" && \
    sed -i -r "s/\"database\"[[:blank:]]*:[[:blank:]]*\"[[:alnum:]]+\"/\"database\": \"$DB_NAME\"/" "$DIR/documentserver/CoAuthoringService/CoAuthoring/sources/config.json" && \
    sed -i -r "s/\"user\"[[:blank:]]*:[[:blank:]]*\"[[:alnum:]_]+\"/\"user\": \"$DB_USER\"/" "$DIR/documentserver/CoAuthoringService/CoAuthoring/sources/config.json" && \
    sed -i -r "s/\"pass\"[[:blank:]]*:[[:blank:]]*\"[[:alnum:]_]+\"/\"pass\": \"$DB_PWD\"/" "$DIR/documentserver/CoAuthoringService/CoAuthoring/sources/config.json"

ADD mysqld.conf /etc/supervisor/conf.d/
RUN mkdir -p "$LOG_DIR/documentserver/CoAuthoringService" "$LOG_DIR/documentserver/DocService" "$LOG_DIR/documentserver/FileConverterService" "$LOG_DIR/documentserver/LibreOfficeService" "$LOG_DIR/documentserver/SpellCheckerService" "$LOG_DIR/documentserver/WatchDogService" "$APP_DIR/documentserver/App_Data" "$DIR/Data" && \
    chown onlyoffice:onlyoffice -R "$DIR" && \
    chown onlyoffice:onlyoffice -R "$LOG_DIR" && \
    chown onlyoffice:onlyoffice -R "$APP_DIR"
RUN "$DIR/documentserver/Tools/AllFontsGen" "/usr/share/fonts" "$DIR/documentserver/DocService/OfficeWeb/sdk/Common/AllFonts.js" "$DIR/documentserver/DocService/OfficeWeb/sdk/Common/Images" "$DIR/documentserver/FileConverterService/Bin/font_selection.bin"
RUN mozroots --import --sync --machine --quiet
RUN mkdir -p /etc/mono/registry/LocalMachine && \
    mkdir -p /usr/share/.mono/keypairs && \
    rm -f /etc/nginx/sites-enabled/default
ADD nginx.conf /etc/supervisor/conf.d/

# refactor /app/onlyoffice/run-document-server.sh
RUN sed "/user=/s/onlyoffice/root/" -i /etc/supervisor/conf.d/CoAuthoringService.conf && \
    sed "/user=/s/onlyoffice/root/" -i /etc/supervisor/conf.d/DocService.conf && \
    sed "/user=/s/onlyoffice/root/" -i /etc/supervisor/conf.d/FileConverterService.conf && \
    sed "/user=/s/onlyoffice/root/" -i /etc/supervisor/conf.d/LibreOfficeService.conf && \
    sed "/user=/s/onlyoffice/root/" -i /etc/supervisor/conf.d/SpellCheckerService.conf && \
    sed "/sudo /s/-u onlyoffice//" -i /var/www/onlyoffice/documentserver/Tools/CheckDocService.sh && \
    sed "/sudo /s/-u onlyoffice//" -i /var/www/onlyoffice/documentserver/Tools/GenerateAllFonts.sh && \
    chown root /var/www/onlyoffice && \
    chown root /var/lib/onlyoffice && \
    usermod -G root -a www-data

ADD config /app/onlyoffice/setup/config/
ADD run-document-server.sh /app/onlyoffice/run-document-server.sh

VOLUME ["/var/log/onlyoffice"]
VOLUME ["/var/www/onlyoffice/Data"]

EXPOSE 80
EXPOSE 443

CMD ["/usr/bin/supervisord"]
