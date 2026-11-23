# dmgbuild layout of Trebuchet.dmg: the designed background (660 x 420 pt, 1x + 2x in one .tiff),
# the app on the left, the Applications link on the right. Used by .github/scripts/sign-app.sh:
#   dmgbuild -s settings.py -D app=<Trebuchet.app> -D background=<background.tiff> "Trebuchet 2.1" Trebuchet-2.1.dmg
import os.path

app = defines["app"]  # noqa: F821 (dmgbuild provides `defines`)
appname = os.path.basename(app)

format = "UDZO"
filesystem = "HFS+"
files = [app]
symlinks = {"Applications": "/Applications"}

background = defines["background"]  # noqa: F821
window_rect = ((200, 140), (660, 420))
default_view = "icon-view"
show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False
include_icon_view_settings = True
icon_size = 128
text_size = 13
arrange_by = None
icon_locations = {appname: (170, 215), "Applications": (490, 215)}
