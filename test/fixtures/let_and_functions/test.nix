let
  x = 1;
  y = 2;
  add = a: b: a + b;
  result = add x y;
in
{
  inherit result;
  doubled = result * 2;
}
