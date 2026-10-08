# TI-style Ans: an operator typed as the first character of an empty cell is
# prefixed with `_`, the previous result. Only once there is an Out[n] to refer
# to, so a fresh session still takes `-5` or `%timeit` as typed.
#
# To get the bare operator (a negative literal, a %magic), start the cell with
# a space: IPython strips the leading indentation before running it.

from prompt_toolkit.enums import DEFAULT_BUFFER
from prompt_toolkit.filters import Condition, emacs_insert_mode, has_focus, vi_insert_mode

_ip = get_ipython()


@Condition
def _empty_with_ans():
    return _ip.pt_app.app.current_buffer.text == "" and bool(_ip.user_ns.get("Out"))


_filter = has_focus(DEFAULT_BUFFER) & (vi_insert_mode | emacs_insert_mode) & _empty_with_ans

for _op in "%/*+-":
    @_ip.pt_app.key_bindings.add(_op, filter=_filter)
    def _insert_ans(event):
        event.current_buffer.insert_text("_" + event.data)
