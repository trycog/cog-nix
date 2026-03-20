let
  x = 1;
  y = 2;
in
{
  inherit x y;
  z = with { a = 10; }; a;
}
