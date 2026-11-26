from sympy.parsing.latex import parse_latex


def latex(expression: str) -> float:
    return float(parse_latex(expression, backend="lark").evalf())
