FROM centos:7

ENV APP_NAME ckan
ENV APP_HOME /srv/app/$APP_NAME
ENV APP_CONFIG /etc/app
ENV APP_CONFIG_FILE $APP_CONFIG/app.ini
ENV CKAN_CONFIG /etc/ckan
ENV CKAN_DB_USER ckan
ENV CKAN_DB_PASS 123456
ENV CKAN_DB_NAME ckan
ENV DATASTORE_DB_USER datastore_default
ENV DATASTORE_DB_PASS 123456
ENV DATASTORE_DB_NAME datastore_default
ENV CONFIG_FILE ckan.ini
ENV STORE_PATH /srv/app/store

RUN yum -y update; \
    yum -y install epel-release; \
    yum -y install http://yum.postgresql.org/9.4/redhat/rhel-7-x86_64/pgdg-centos94-9.4-1.noarch.rpm; \
    yum -y install httpd python-virtualenv mod_wsgi git postgresql94 postgresql94-devel gcc supervisor cronie; \
    yum clean all

# Should be $APP_NAME
ADD ./docker/apache/app.conf /etc/httpd/conf.d/
ADD ./docker/apache/app.wsgi $CKAN_CONFIG/

# Install requirements
RUN ln -s /usr/pgsql-9.4/bin/* /usr/local/bin/; \
    mkdir -p $APP_HOME; \
    virtualenv --no-site-packages $APP_HOME; \
    $APP_HOME/bin/pip install -e 'git+https://github.com/ckan/ckan.git@release-v2.3.1#egg=ckan'; \
    $APP_HOME/bin/pip install -r $APP_HOME/src/ckan/requirements.txt; \
    $APP_HOME/bin/paster make-config ckan ${CKAN_CONFIG}/${CONFIG_FILE}; \
    $APP_HOME/bin/pip install ckanext-pdfview; \
    $APP_HOME/bin/pip install -e git+https://github.com/ckan/ckanext-harvest.git@89b6ad2ce1#egg=ckanext-harvest; \
    $APP_HOME/bin/pip install -r $APP_HOME/src/ckanext-harvest/pip-requirements.txt; \
    $APP_HOME/bin/pip install -e git+https://github.com/ckan/ckanext-geoview.git#egg=ckanext-geoview; \
    $APP_HOME/bin/pip install -e git+https://github.com/okfn/ckanext-disqus#egg=ckanext-disqus

# Add dados_cmporto_pt plugin
ADD . $APP_HOME/src/ckan/ckanext-dados_cmporto_pt

# Set configurations
RUN mkdir -p $CKAN_CONFIG; \
    "$APP_HOME"/bin/paster --plugin=ckan config-tool "$CKAN_CONFIG/$CONFIG_FILE" -e \
      "ckan.site_url                                   = http://dados.cm-porto.pt" \
      "sqlalchemy.url                                  = postgresql://$CKAN_DB_USER:$CKAN_DB_PASS@db/$CKAN_DB_NAME" \
      "solr_url                                        = http://solr:8983/solr/ckan" \
      "ckan.datastore.write_url                        = postgresql://$CKAN_DB_USER:$CKAN_DB_PASS@db/$DATASTORE_DB_NAME" \
      "ckan.datastore.read_url                         = postgresql://$DATASTORE_DB_USER:$DATASTORE_DB_PASS@db/$DATASTORE_DB_NAME" \
      "ckan.auth.create_unowned_dataset                = false" \
      "ckan.auth.create_dataset_if_not_in_organization = false" \
      "ckan.auth.user_create_groups                    = false" \
      "ckan.auth.user_create_organizations             = false" \
      "ckan.auth.user_delete_groups                    = false" \
      "ckan.auth.user_delete_organizations             = false" \
      "ckan.plugins                                    = datastore disqus resource_proxy text_view image_view recline_view pdf_view stats geo_view shapefile_view harvest guia_harvester dados_cmporto_pt  gbridge_ui od_ui_plugin" \
      "ckan.favicon                                    = /img/icon-cmp-blue.png" \
      "ckan.locale_default                             = pt_PT" \
      "ckan.locale_order                               = pt_PT" \
      "ckan.locales_filtered_out                       = en_GB pt_BR" \
      "ckan.max_resource_size                          = 512" \
      "ckan.views.default_views                        = webpage_view pdf_view text_view image_view recline_view geo_view"; \
    "$APP_HOME"/bin/paster --plugin=ckan config-tool "$CKAN_CONFIG/$CONFIG_FILE" \
      "package_hide_extras  =  fornecimento_externo 	identificacao_responsavel_fornecedor responsavel_editor_nome responsavel_editor_email responsavel_editor_telefone responsavel_editor_und_organica  responsavel_tutor_nome responsavel_tutor_email responsavel_tutor_telefone responsavel_tutor_und_organica   restricoes_acesso_interno limitacoes fornecimento_externo limitacoes_fornecimento_externo  principais_utilizadores dataset_data_atualizacao dataset_data_criacao origem_geometria  codificacao_caracteres notas_metodologicas" \
      "ckan.storage_path                               = $STORE_PATH" \
      "ckan.i18n_directory                             = $APP_HOME/src/ckan/ckanext-dados_cmporto_pt/ckanext/dados_cmporto_pt" \
      "ckan.tracking_enabled                           = true" \
      "ckan.search.show_all_types                      = true" \
      "ckanext.geo_view.ol_viewer                      = wms"; \
    cd $APP_HOME/src/ckan/ckanext-dados_cmporto_pt && "$APP_HOME"/bin/python setup.py develop; \
    ln -s $APP_HOME/src/ckan/ckan/config/who.ini $CKAN_CONFIG/who.ini

# Add APP Settings
RUN mkdir -p $APP_CONFIG
ADD ./app.ini $APP_CONFIG_FILE

# Supervisor to run ckan and harvest jobs
RUN mkdir -p /etc/supervisor/conf.d
RUN mkdir -p /var/log/ckan/std
COPY ./docker/ckan/supervisord.conf /etc/supervisor/conf.d/supervisord.conf
COPY ./docker/ckan/crontab.root /var/spool/cron/root
COPY ./docker/ckan/ckan-harvest-gatherer.bash /usr/local/bin/
COPY ./docker/ckan/ckan-harvest-fetcher.bash /usr/local/bin/
COPY ./docker/ckan/ckan-harvest-run.bash /usr/local/bin/
RUN chmod +x /usr/local/bin/ckan-harvest-gatherer.bash; \
    chmod +x /usr/local/bin/ckan-harvest-fetcher.bash; \
    chmod +x /usr/local/bin/ckan-harvest-run.bash; \
    chmod 600 /var/spool/cron/root; \
    env > /etc/envvars

# Copy start script
COPY ./docker/ckan/utils.bash /usr/local/bin/
COPY ./docker/ckan/start.bash /usr/local/bin/
RUN chmod +x /usr/local/bin/start.bash; \
    touch /root/start.lock

# Copy apache start script
COPY ./docker/apache/httpd-foreground /usr/local/bin/
RUN chmod +x /usr/local/bin/httpd-foreground

# Port, command and Shared data
EXPOSE 80
CMD ["/usr/bin/supervisord", "-c", "/etc/supervisor/conf.d/supervisord.conf"]
