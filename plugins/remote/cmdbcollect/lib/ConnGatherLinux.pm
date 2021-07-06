#!/usr/bin/perl
use FindBin;
use lib $FindBin::Bin;

package ConnGatherLinux;
use ConnGatherBase;
@ISA = qw(ConnGatherBase);    #继承BASECollector

#父类的实现就是基于Linux的，所以这里不需要写任何代码
1;
