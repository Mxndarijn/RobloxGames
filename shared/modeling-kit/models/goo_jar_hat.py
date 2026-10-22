# Goo jar tower theme mesh (JAR_THEME, not classic): the theme's hat on the mascot, radius 1 like goo_jar_mascot (the game
# scales it with the mascot). Build: JAR_THEME=garden python iterate.py models/goo_jar_hat.py --name goo_jar_hat@garden
from models._goo_jar import *

ship("goo_jar_hat", mascot_hat())
