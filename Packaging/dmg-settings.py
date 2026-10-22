# Run dmgbuild from the app repository root, passing -D app=/path/to/Campfire.app.
import os

application = os.path.abspath(defines['app'])
files = [(application, 'Campfire.app')]
symlinks = {'Applications': '/Applications'}
background = os.path.abspath('Packaging/background.png')
format = 'UDZO'
filesystem = 'HFS+'
window_rect = ((180, 120), (768, 512))
default_view = 'icon-view'
icon_locations = {'Campfire.app': (200, 300), 'Applications': (568, 300), '.background.png': (2000, 2000)}
icon_size = 104
text_size = 14
hide_extensions = ['Campfire.app']
show_toolbar = False
show_sidebar = False
show_status_bar = False
show_pathbar = False
show_tab_view = False
arrange_by = None
