/*
 * Hunt - a framework for web and console application based on Collie using Dlang development
 *
 * Copyright (C) 2015-2016  Shanghai Putao Technology Co., Ltd 
 *
 * Developer: putao's Dlang team
 *
 * Licensed under the BSD License.
 *
 */
module hunt.view.examples.usage;

import 
  hunt.view,
  std.stdio,
  std.string;

void abasic()
{
    auto tlate = compile_temple!"foo, bar, baz";
    writeln(tlate.toString()); // Prints "foo, bar, baz"
}
