# silence warnings
import warnings

warnings.filterwarnings("ignore")

# https://docs.sympy.org/latest/install.html#mpmath-installation
import sys
import mpmath

sys.modules["sympy.mpmath"] = mpmath

# real imports
from sympy import *

init_printing(use_unicode=True)  # my terminals can handle it
# every key on my ti89
a = Symbol("a")
b = Symbol("b")
c = Symbol("c")
d = Symbol("d")
e = Symbol("e")
f = Symbol("f")
g = Symbol("g")
h = Symbol("h")
i = Symbol("i")
j = Symbol("j")
k = Symbol("k")
l = Symbol("l")
m = Symbol("m")
n = Symbol("n")
o = Symbol("o")
p = Symbol("p")
q = Symbol("q")
r = Symbol("r")
s = Symbol("s")
t = Symbol("t")
u = Symbol("u")
v = Symbol("v")
w = Symbol("w")
x = Symbol("x")
y = Symbol("y")
z = Symbol("z")
theta = Symbol("theta")
