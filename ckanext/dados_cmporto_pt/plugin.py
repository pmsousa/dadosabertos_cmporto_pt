# -*- coding: utf-8 -*-

import ckan.plugins as plugins
import ckan.plugins.toolkit as toolkit

import logging
log = logging.getLogger(__name__)


class CMPortoPlugin(plugins.SingletonPlugin):
    '''Theme for the dados.cmporto.pt portal
    '''
    plugins.implements(plugins.IConfigurer)
    plugins.implements(plugins.IRoutes, inherit=True)

    # IConfigurer

    def update_config(self, config_):
        toolkit.add_template_directory(config_, 'templates')
        toolkit.add_public_directory(config_, 'public')
        toolkit.add_resource('public', 'dados_cmporto_pt')
        

    # IRoutes

    def before_map(self, map):
        """This IRoutes implementation overrides the standard
        ``/ckan-admin/config`` behaviour with a custom controller.
        """
        map.connect('/ckan-admin/config', controller='ckanext.dados_cmporto_pt.controller:AdminController', action='config')
        map.connect('/terms-of-use', controller='ckanext.dados_cmporto_pt.controller:StaticPagesController', action='terms_of_use')
        map.connect('/privacy-policy', controller='ckanext.dados_cmporto_pt.controller:StaticPagesController', action='privacy_policy')
        map.connect('/moderation-policy', controller='ckanext.dados_cmporto_pt.controller:StaticPagesController', action='moderation_policy')
        map.connect('/license', controller='ckanext.dados_cmporto_pt.controller:StaticPagesController', action='list_license')
        return map

class ShapefilePlugin(plugins.SingletonPlugin):
    plugins.implements(plugins.IResourceView, inherit=True)
    plugins.implements(plugins.IConfigurable, inherit=True)

    def configure(self, config):
        self.gapi_key = config.get('ckanext.geoview.gapi_key', None)

    def info(self):
        return {'name': 'shp_view',
                'title': plugins.toolkit._('Shapefile Viewer (GeoStore)'),
                'icon': 'globe',
                'iframed': True,
                'default_title': plugins.toolkit._('Map viewer')
                }

    def can_view(self, data_dict):
        resource = data_dict.get('resource', None)
        if resource:
            url_type = resource.get('url_type', '')
            format_lower = resource.get('format', '').lower()
            if url_type == 'upload' and format_lower == 'shp':
                return self.proxy_enabled
        return False

    def view_template(self, context, data_dict):
        return 'dataviewer/openlayers2.html'

    def _get_wms_url(self, resource):
        return '/dataset/{0}/resource/{1}/wms'.format(resource.get('package_id', None), resource.get('id', None))

    def setup_template_variables(self, context, data_dict):
        resource = data_dict.get('resource', None)
        resource['original_format'] = resource.get('format', None)
        resource['format'] = 'wms'
        resource['original_url'] = resource.get('url', None)
        resource['url'] = self._get_wms_url(resource)
        return {'proxy_service_url': self._get_wms_url(resource),
            'proxy_url': self._get_wms_url(resource),
            'gapi_key': self.gapi_key}
