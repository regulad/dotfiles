from sympy.parsing.latex import parse_latex


def latex(expression: str) -> Expr:
    return parse_latex(expression, backend="lark")
