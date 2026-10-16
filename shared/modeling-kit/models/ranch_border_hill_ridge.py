# ranch_border_hill_ridge: long low grassy ridge with a few firs, closes a stretch of horizon (~58 x 20 x 16).
import random
from lib import *
from models._border_v3 import *

R = random.Random(241)
parts = hill("Ridge", 0, 0, 58.0, 20.0, 10.0, R,
             humps=((-0.55, 0.0, 0.7, 0.9, 0.8), (0.1, 0.05, 0.6, 0.95, 1.0), (0.65, -0.05, 0.55, 0.85, 0.7)),
             trees=[(-20.0, 2.5, 11.0), (-14.0, 3.4, 8.0), (10.0, 3.0, 12.0), (17.0, 2.0, 8.5), (3.0, 4.5, 7.0)],
             rocks=[(-4.0, -3.4, (3.4, 2.8, 2.4))], tufts_n=10, NS=30, NR=7)
finish("ranch_border_hill_ridge", parts)
