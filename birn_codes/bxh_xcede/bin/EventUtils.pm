package EventUtils;

use strict;
use warnings;

use FindBin;
use lib "$FindBin::Bin";
use File::Which;

use XMLUtils;

use Config;


BEGIN {
  use Exporter ();
  our ($VERSION, @ISA, @EXPORT, @EXPORT_OK, %EXPORT_TAGS);

  # if using RCS/CVS, this may be preferred
  $VERSION = sprintf "%d.%03d", q$Revision: 1.1 $ =~ /(\d+)/g;

  @ISA         = qw(Exporter);
  @EXPORT      = qw(&replace_onsetdur &read_and_merge_events &sort_events &trans_events &xcede_query_to_xpath);
  @EXPORT_OK   = qw($opt_verbose);
}
our @EXPORT_OK;

our $opt_verbose = 0;

sub replace_onsetdur {
  # appending children is slow in XML::XPath, so avoid it when
  # possible
  my ($doc, $node, $newonset, $newdur) = @_;
  my @onsettextnodes = XMLUtils::xpathFindNodes('onset/text()', $node);
  my @durtextnodes = XMLUtils::xpathFindNodes('duration/text()', $node);
  if (@onsettextnodes > 1) {
    print STDERR "Too many onset nodes???\n";
    exit -1;
  }
  if (@durtextnodes > 1) {
    print STDERR "Too many duration nodes???\n";
    exit -1;
  }
  if (@onsettextnodes == 0) {
    my $newonsetnode = $doc->createElement('onset');
    $node->appendChild($newonsetnode);
    my $newonsettextnode = $doc->createTextNode("$newonset");
    $newonsetnode->appendChild($newonsettextnode);
    # do it in this order because it seems XML::XPath only increments
    # the global position number for each following node by a constant,
    # no matter if the appended node has children itself.  So, just
    # make sure we are appending from the top down.
  } else {
    $onsettextnodes[0]->setNodeValue("$newonset");
  }
  if (@durtextnodes == 0) {
    my $newdurnode = $doc->createElement('duration');
    $node->appendChild($newdurnode);
    my $newdurtextnode = $doc->createTextNode("$newonset");
    $newdurnode->appendChild($newdurtextnode);
    # do it in this order because it seems XML::XPath only increments
    # the global position number for each following node by a constant,
    # no matter what the content of the appended node is.  So, just
    # make sure we are appending from the top down.
  } else {
    $durtextnodes[0]->setNodeValue("$newdur");
  }
}

sub read_and_merge_events {
  my @xmlfiles = @_;
  my $mergedoc = XMLUtils::createDocument('events');
  my ($mergeeventselem, ) =
    XMLUtils::xpathFindNodes('events', $mergedoc);
  for my $xmlfile (@xmlfiles) {
    # find all <event> elements
    my $doc = XMLUtils::readXMLFile($xmlfile);
    # first find <events> elements
    my @eventselems = ();
    my @queue = ();
    for (my $child = $doc->getFirstChild();
	 defined($child);
	 $child = $child->getNextSibling()) {
      push @queue, $child;
    }
    while (@queue > 0) {
      my $node = shift @queue;
      if ($node->getNodeTypeStr() eq 'ELEMENT') {
	if ($node->getNodeName() eq 'events') {
	  push @eventselems, $node;
	} else {
	  for (my $child = $node->getFirstChild();
	       defined($child);
	       $child = $child->getNextSibling()) {
	    push @queue, $child;
	  }
	}
      }
    }
    # now find each child <event> element
    my @eventelems;
    for my $eventselem (@eventselems) {
      for (my $child = $eventselem->getFirstChild();
	   defined($child);
	   $child = $child->getNextSibling()) {
	if ($child->getNodeTypeStr() eq 'ELEMENT' &&
	    $child->getNodeName() eq 'event') {
	  push @eventelems, $child;
	}
      }
    }
    # for each <event> element, add them to mergedoc
    for my $eventelem (@eventelems) {
      XMLUtils::clone_and_append_child($mergedoc, $mergeeventselem, $eventelem);
    }
#    $doc->dispose();
  }

  return ($mergedoc, $mergeeventselem);
}

#####################
# sort event document
sub sort_events {
  my ($doc_in, $eventselem_in) = @_;
  my @sortedeventlist = ();
  for (my $child = $eventselem_in->getFirstChild();
       defined($child);
       $child = $child->getNextSibling()) {
    my $onset = XMLUtils::xpathFindValue('onset', $child);
    my $dur = XMLUtils::xpathFindValue('duration', $child);
    next if !defined($onset);
    if ($onset =~ /^\s*$/) {
      next;
    }
    if (!defined($dur) || $dur =~ /^\s*$/) {
      $dur = 0;
    }
    push @sortedeventlist, [$onset, $dur, $child];
  }
  @sortedeventlist = sort {
    ($a->[0] <=> $b->[0]) || ($a->[1] <=> $b->[1])
  } @sortedeventlist;
  my $sortdoc = XMLUtils::createDocument('events');
  my ($sorteventselem, ) =
    XMLUtils::xpathFindNodes('events', $sortdoc);
  for my $event (@sortedeventlist) {
    $event->[2] = XMLUtils::clone_and_append_child($sortdoc, $sorteventselem, $event->[2]);
  }
  return ($sortdoc, $sorteventselem, @sortedeventlist);
}

sub trans_events {
  my ($sortdoc, @sortedeventlist) = @_;
  print STDERR "Making transition document:\n" if ($opt_verbose);
  my $transdoc = XMLUtils::createDocument('events');
  my ($transeventselem, ) =
    XMLUtils::xpathFindNodes('events', $transdoc);
  my $epsilon = 0.0000001;	# nanosecond granularity
  while (@sortedeventlist > 1) {
    my $eventA = $sortedeventlist[0];
    my $eventB = $sortedeventlist[1];
    my ($onsetA, $durA, $nodeA) = @$eventA;
    my ($onsetB, $durB, $nodeB) = @$eventB;
    print STDERR "A: [$onsetA, $durA)\tB: [$onsetB, $durB]\n" if ($opt_verbose);
    if ($onsetA != $onsetB && $onsetA + $durA <= $onsetB) {
      print STDERR " Retiring A (no overlap)\n" if ($opt_verbose);
      # no interval overlap, so eventA is good to go
      XMLUtils::clone_and_append_child($transdoc, $transeventselem, $nodeA);
      shift @sortedeventlist;
      next;
    }
    if (abs($onsetA - $onsetB) < $epsilon && abs($durA - $durB) < $epsilon) {
      # intervals A and B are equal
      # need to merge B into A and delete B
      print STDERR " Merging B into A, deleting B\n" if ($opt_verbose);
      my $newnodeA = $nodeA->cloneNode(1);
      my @valuenodes = XMLUtils::xpathFindNodes('value', $nodeB);
      for my $valuenode (@valuenodes) {
	XMLUtils::clone_and_append_child($sortdoc, $newnodeA, $valuenode);
      }
      $sortedeventlist[0]->[2] = $newnodeA;
      # delete interval B
      $sortedeventlist[1] = $sortedeventlist[0];
      shift @sortedeventlist;
      next;
    }
    # if we get here, A and B overlap, and starting point of A
    # is no greater than starting point of B, because they are
    # sorted
    if (abs($durA) < $epsilon) {
      # Interval A [x,x], is a single point and starts at the
      # same time as interval B [x,y], by virtue of ordering
      # constraints.  Merge B into A, but keep B.
      print STDERR " Merging B into A, keeping B\n" if ($opt_verbose);
      my $newnodeA = $nodeA->cloneNode(1);
      my @valuenodes = XMLUtils::xpathFindNodes('value', $nodeB);
      for my $valuenode (@valuenodes) {
	XMLUtils::clone_and_append_child($sortdoc, $newnodeA, $valuenode);
      }
      # eventA is finished
      print STDERR " Retiring A\n" if ($opt_verbose);
      XMLUtils::clone_and_append_child($transdoc, $transeventselem, $newnodeA);
      shift @sortedeventlist;
      next;
    }
    if ($onsetA < $onsetB) {
      # Interval A [w,x) overlaps and starts before
      # interval B [y,z):
      #     |-----A-----|
      #  <--w-----y-----x-----z-->
      #           |-----B-----|
      # or
      #     |--------A--------|
      #  <--w-----y-----z-----x-->
      #           |--B--|
      # Split interval A into two fragments C [a1,b1) and D [b1,a2):
      #     |--C--|--D--|
      #  <--w-----y-----x-----z-->
      #           |-----B-----|
      # or
      #     |--C--|-----D-----|
      #  <--w-----y-----z-----x-->
      #           |--B--|
      #
      my $nodeC = $nodeA->cloneNode(1);
      my $nodeD = $nodeA->cloneNode(1);
      my $onsetC = $onsetA;
      my $durC = $onsetB - $onsetA;
      my $onsetD = $onsetB;
      my $durD = ($onsetA + $durA) - $onsetB;
      replace_onsetdur($sortdoc, $nodeC, $onsetC, $durC);
      replace_onsetdur($sortdoc, $nodeD, $onsetD, $durD);
      print STDERR " Splitting A into two intervals:\n" if ($opt_verbose);
      print STDERR "  C: [$onsetC, $durC]\tD: [$onsetD, $durD]\n" if ($opt_verbose);
      print STDERR " Retiring C\n" if ($opt_verbose);
      # nodeA now has interval C, and nodeD has interval D
      # C is guaranteed to not overlap any other intervals,
      # so we can get rid of eventA
      XMLUtils::clone_and_append_child($transdoc, $transeventselem, $nodeC);
      shift @sortedeventlist;
      # add new interval D to sorted event list
      my $putbefore = -1;
      for my $ind (0..$#sortedeventlist) {
	my ($tmponset, $tmpdur, $tmpevent) = @{$sortedeventlist[$ind]};
	if ($tmponset > $onsetD || ($tmponset == $onsetD && $tmpdur > $durD)) {
	  $putbefore = $ind;
	  last;
	}
      }
      my $neweventref = [$onsetD, $durD, $nodeD];
      if ($putbefore == -1) {
	push @sortedeventlist, $neweventref;
      } else {
	splice(@sortedeventlist, $putbefore, 0, $neweventref);
      }
      next;
    }
    if (abs($onsetA - $onsetB) < $epsilon && $durA < $durB) {
      # Interval A [x,y) starts at the same time, but
      # ends before interval B [x,z):
      #     |--A--|
      #  <--x-----y-----z-->
      #     |-----B-----|
      # Split interval B into two fragments C [x,y) and D [y,z).
      #     |--A--|
      #  <--x-----y-----z-->
      #     |--C--|--D--|
      #
      my $nodeC = $nodeB->cloneNode(1);
      my $nodeD = $nodeB->cloneNode(1);
      my $onsetC = $onsetB;
      my $durC = $durA;
      my $onsetD = $onsetB + $durA;
      my $durD = $durB - $durA;
      replace_onsetdur($sortdoc, $nodeC, $onsetC, $durC);
      replace_onsetdur($sortdoc, $nodeD, $onsetD, $durD);
      print STDERR " Splitting B into two intervals:\n" if ($opt_verbose);
      print STDERR "  C: [$onsetC, $durC]\tD: [$onsetD, $durD]\n" if ($opt_verbose);
      # nodeB now has interval C, and nodeD has interval D.
      # new intervals C and D need to be added to sorted event list.
      # interval C can just take B's old place (right after A, since
      # they share the same onset and duration)
      $eventB->[0] = $onsetC;
      $eventB->[1] = $durC;
      $eventB->[2] = $nodeC;
      # add new interval D to sorted event list
      my $putbefore = -1;
      for my $ind (0..$#sortedeventlist) {
	my ($tmponset, $tmpdur, $tmpevent) = @{$sortedeventlist[$ind]};
	if ($tmponset > $onsetD || ($tmponset == $onsetD && $tmpdur > $durD)) {
	  $putbefore = $ind;
	  last;
	}
      }
      my $neweventref = [$onsetD, $durD, $nodeD];
      if ($putbefore == -1) {
	push @sortedeventlist, $neweventref;
      } else {
	splice(@sortedeventlist, $putbefore, 0, $neweventref);
      }
      next;
    }
    print STDERR "EventUtils: Internal error: events are not sorted correctly?\n";
  }
  # there should be at most one element left in sortedeventlist
  map {
    my $node = $_->[2];
    XMLUtils::clone_and_append_child($transdoc, $transeventselem, $node);
  } @sortedeventlist;

  return ($transdoc, $transeventselem);
}

## this stuff is for converting XCEDE event queries to XPath

sub T_INVALID    { return 0; }
sub T_NUMTOKEN   { return 1; }
sub T_STRTOKEN   { return 2; }
sub T_PARAMTOKEN { return 3; }
sub T_OPENPAREN  { return 4; }
sub T_CLOSEPAREN { return 5; }
sub T_COMMA      { return 6; }
sub T_DASH       { return 7; }
sub T_AND        { return 8; }
sub T_OR         { return 9; }
sub T_INEQ_OP    { return 10; }
sub T_EQ_OP      { return 11; }

sub S_INVALID    { return 0; }
sub S_QUERY      { return 1; }
sub S_PQUERY     { return 2; }
sub S_CONDITION  { return 3; }

my %magicparams =
  (
   '$onset' => 'onset',
   'onset' => 'onset',
   '$duration' => 'duration',
   'duration' => 'duration',
   '$type' => '@type',
   'type' => '@type',
   '$units' => 'units',
   'units' => 'units',
   '$description' => 'description',
   'description' => 'description',
  );

sub NEXTTOKEN {
  my ($tokenlistref, $tokennum) = @_;
  if ($tokennum + 1 > $#$tokenlistref) {
    my $query = join(" ", map { $_->[1] } @$tokenlistref);
    print STDERR "Expecting more after:\n $query\n";
    exit -1;
  }
  $tokennum++;
  return ($tokennum, @{$tokenlistref->[$tokennum]});
}

sub xcede_query_to_xpath {
  my ($queryin, $noimplicittest, $valuelevel) = @_;

  my @tokenlist = ();
  my @stack = ();

  if (!defined($noimplicittest)) {
    $noimplicittest = 0;
  }

  if (!defined($valuelevel)) {
    $valuelevel = 0;
  }

  # first convert into tokens
  while (length($queryin) > 0) {
    my $token = undef;
    my $tokentype = T_INVALID;
    $queryin =~ s/^\s+//;
    if ($queryin =~ s/^(\d+\.\d*|\d+|\.\d+)//) {
      # NUMTOKEN   ::=  DIGIT+ "." DIGIT*
      #              |  DIGIT+
      #              |  "." DIGIT+
      $token = $1;
      $tokentype = T_NUMTOKEN;
    } elsif ($queryin =~ s/^(\'[^\']*\'|\"[^\"]*\")//) {
      # STRTOKEN   ::=  "'" STRCHAR1* "'"
      #              |  '"' STRCHAR2* '"'
      # STRCHAR1   ::= any ASCII character except single quote (')
      # STRCHAR2   ::= any ASCII character except double quote (")
      $token = $1;
      $tokentype = T_STRTOKEN;
    } elsif ($queryin =~ s/^((\$|\%)?[_A-Za-z][._A-Za-z0-9]*)//) {
      # PARAMTOKEN ::=  "$" PARAMSTART PARAMCHAR*
      #              |  "%" PARAMSTART PARAMCHAR*
      #              |      PARAMSTART PARAMCHAR*
      # PARAMSTART ::=  "_" | LETTER
      # PARAMCHAR  ::=  "." | "_" | LETTER | DIGIT
      $token = $1;
      $tokentype = T_PARAMTOKEN;
    } elsif ($queryin =~ s/^(\()//) {
      $token = $1;
      $tokentype = T_OPENPAREN;
    } elsif ($queryin =~ s/^(\))//) {
      $token = $1;
      $tokentype = T_CLOSEPAREN;
    } elsif ($queryin =~ s/^(,)//) {
      $token = $1;
      $tokentype = T_COMMA;
    } elsif ($queryin =~ s/^(-)//) {
      $token = $1;
      $tokentype = T_DASH;
    } elsif ($queryin =~ s/^(\&)//) {
      $token = $1;
      $tokentype = T_AND;
    } elsif ($queryin =~ s/^(\|)//) {
      $token = $1;
      $tokentype = T_OR;
    } elsif ($queryin =~ s/^(<=|>=|<|>)//) {
      $token = $1;
      # INEQ_OP  ::=  "<=" | ">=" | "<" | ">"
      $tokentype = T_INEQ_OP;
    } elsif ($queryin =~ s/^(==|!=)//) {
      # EQ_OP    ::=  "==" | "!="
      $token = $1;
      $tokentype = T_EQ_OP;
    } else {
      print STDERR "Unrecognized syntax at:\n $queryin\n";
      exit -1;
    }
    push @tokenlist, [ $tokentype, $token ];
  }

  if (@tokenlist == 0) {
    print STDERR "input query is empty!\n";
    exit -1;
  }

  # Starting point is thus:
  #   QUERY ::= "(" QUERY ")"
  #           | QUERY "&" QUERY
  #           | QUERY "|" QUERY
  #           | CONDITION
  # XPath has the same order of operations, so we don't need to
  # worry about re-ordering anything or adding parentheses.
  # For our purposes, then, the above is equivalent to:
  #   QUERY  ::= PQUERY    "&" QUERY
  #            | PQUERY    "|" QUERY
  #            | PQUERY
  #            | CONDITION "&" QUERY
  #            | CONDITION "|" QUERY
  #            | CONDITION
  #   PQUERY ::= "(" QUERY ")"
  # The state machine below uses "goto"s for clarity!

  my $queryout = '';
  push @stack, S_QUERY;
  my $tokennum = 0;
  my $numtokens = scalar(@tokenlist);
  while (@stack && $tokennum <= $#tokenlist) {
    my ($tokentype, $token) = @{$tokenlist[$tokennum]};
    if ($tokentype == T_OPENPAREN) {
      push @stack, S_PQUERY;
      $queryout .= "(";
      $tokennum++;
      next;
    }
    # we didn't find an open parenthesis, so parse a CONDITION
    my $lvalue = undef;
    my $ltype = T_INVALID;
    my $rvalue = undef;
    if ($tokentype != T_PARAMTOKEN &&
	$tokentype != T_NUMTOKEN &&
	$tokentype != T_STRTOKEN) {
      my $querystart = join(" ", map { $_->[1] } @tokenlist[0..$tokennum-1]);
      my $queryend = join(" ", map { $_->[1] } @tokenlist[$tokennum..$#tokenlist]);
      print STDERR "param name, string, or number expected after:\n $querystart\nbut got:\n $queryend\n";
      exit -1;
    }
    $ltype = $tokentype;
    if ($tokentype == T_PARAMTOKEN) {
      if (exists($magicparams{$token})) {
	$lvalue = $magicparams{$token};
      } else {
	$token =~ s/^\%//;
	if (!$valuelevel) {
	  $lvalue .= 'value[';
	}
	$lvalue .= '@name=\'';
	$lvalue .= $token;
	$lvalue .= '\'';
	if (!$valuelevel) {
	  $lvalue .= ']';
	}
      }
    } else {
      $lvalue = $token;
    }
    if ($tokennum + 1 < $numtokens) {
      $tokennum++;
      ($tokentype, $token) = @{$tokenlist[$tokennum]};
    } else {
      $tokennum++;
      $tokentype = T_INVALID;
    }
    if ($tokentype == T_OPENPAREN) {
      my $firstclause = 1;
      if ($ltype != T_PARAMTOKEN) {
	my $querystart = join(" ", map { $_->[1] } @tokenlist[0..$tokennum]);
	print STDERR "Expected param name before paren here:\n $querystart\n";
	exit -1;
      }
      $queryout .= "(";
      ($tokennum, $tokentype, $token) = NEXTTOKEN(\@tokenlist, $tokennum);
      while ($tokentype != T_CLOSEPAREN) {
	if (!$firstclause) {
	  if ($tokentype != T_COMMA) {
	    my $querystart = join(" ", map { $_->[1] } @tokenlist[0..$tokennum-1]);
	    my $queryend = join(" ", map { $_->[1] } @tokenlist[$tokennum..$#tokenlist]);
	    print STDERR "Expected comma or right-paren after:\n $querystart\nbut got:\n $queryend\n";
	    exit -1;
	  }
	  $queryout .= " or ";
	  ($tokennum, $tokentype, $token) = NEXTTOKEN(\@tokenlist, $tokennum);
	}
	$firstclause = 0;
	if ($tokentype == T_INEQ_OP) {
	  my $op = $token;
	  ($tokennum, $tokentype, $token) = NEXTTOKEN(\@tokenlist, $tokennum);
	  if ($tokentype != T_NUMTOKEN) {
	    my $querystart = join(" ", map { $_->[1] } @tokenlist[0..$tokennum-1]);
	    my $queryend = join(" ", map { $_->[1] } @tokenlist[$tokennum..$#tokenlist]);
	    print STDERR "Expected number after:\n $querystart\nbut got:\n $queryend\n";
	    exit -1;
	  }
	  $queryout .= $lvalue;
	  $queryout .= $op;
	  $queryout .= $token;
	} elsif ($tokentype == T_NUMTOKEN) {
	  my $rangebegin = $token;
	  if ($tokennum + 1 < $numtokens &&
	      $tokenlist[$tokennum+1]->[0] == T_DASH) {
	    $tokennum++;
	    ($tokennum, $tokentype, $token) = NEXTTOKEN(\@tokenlist, $tokennum);
	    if ($tokentype != T_NUMTOKEN) {
	      my $querystart = join(" ", map { $_->[1] } @tokenlist[0..$tokennum-1]);
	      my $queryend = join(" ", map { $_->[1] } @tokenlist[$tokennum..$#tokenlist]);
	      print STDERR "Expected number after:\n $querystart\nbut got:\n $queryend\n";
	      exit -1;
	    }
	    my $rangeend = $token;
	    $queryout .= "(";
	    $queryout .= $lvalue;
	    $queryout .= ">=";
	    $queryout .= $rangebegin;
	    $queryout .= " and ";
	    $queryout .= $lvalue;
	    $queryout .= "<=";
	    $queryout .= $rangeend;
	    $queryout .= ")";
	  } else {
	    $queryout .= $lvalue;
	    $queryout .= "=";
	    $queryout .= $token;
	  }
	} else {
	  # should be a string
	  $queryout .= $lvalue;
	  $queryout .= "=";
	  $queryout .= $token;
	}
	($tokennum, $tokentype, $token) = NEXTTOKEN(\@tokenlist, $tokennum);
      }
      $tokennum++;
      $queryout .= ")";
    } elsif ($tokentype == T_INEQ_OP) {
      my $op = $token;
      ($tokennum, $tokentype, $token) = NEXTTOKEN(\@tokenlist, $tokennum);
      if ($tokentype == T_PARAMTOKEN) {
	if (exists($magicparams{$token})) {
	  $rvalue = $magicparams{$token};
	} else {
	  $token =~ s/^%//;
	  if (!$valuelevel) {
	    $rvalue .= 'value[';
	  }
	  $rvalue .= '@name=\'';
	  $rvalue .= $token;
	  $rvalue .= '\'';
	  if (!$valuelevel) {
	    $rvalue .= ']';
	  }
	}
      } elsif ($tokentype == T_NUMTOKEN) {
	$rvalue = $token;
      } else {
	my $querystart = join(" ", map { $_->[1] } @tokenlist[0..$tokennum-1]);
	my $queryend = join(" ", map { $_->[1] } @tokenlist[$tokennum..$#tokenlist]);
	print STDERR "Expected param name or number after:\n $querystart\nbut got:\n $queryend\n";
	exit -1;
      }
      $queryout .= $lvalue;
      $queryout .= $op;
      $queryout .= $rvalue;
      $tokennum++;
    } elsif ($tokentype == T_EQ_OP) {
      my $op = $token;
      if ($op eq '==') {
	$op = "=";
      }
      ($tokennum, $tokentype, $token) = NEXTTOKEN(\@tokenlist, $tokennum);
      if ($tokentype == T_PARAMTOKEN) {
	if (exists($magicparams{$token})) {
	  $rvalue = $magicparams{$token};
	} else {
	  $token =~ s/^%//;
	  if (!$valuelevel) {
	    $rvalue .= 'value[';
	  }
	  $rvalue .= '@name=\'';
	  $rvalue .= $token;
	  $rvalue .= '\'';
	  if (!$valuelevel) {
	    $rvalue .= ']';
	  }
	}
      } elsif ($tokentype == T_NUMTOKEN || $tokentype == T_STRTOKEN) {
	$rvalue = $token;
      } else {
	my $querystart = join(" ", map { $_->[1] } @tokenlist[0..$tokennum-1]);
	my $queryend = join(" ", map { $_->[1] } @tokenlist[$tokennum..$#tokenlist]);
	print STDERR "Expected param name, number, or string after:\n $querystart\nbut got:\n $queryend\n";
	exit -1;
      }
      $queryout .= $lvalue;
      $queryout .= $op;
      $queryout .= $rvalue;
      $tokennum++;
    } else {
      # simple test
      if ($noimplicittest) {
	$queryout .= $lvalue;
      } elsif (!$noimplicittest) {
	$queryout .= $lvalue;
	$queryout .= " and ";
	$queryout .= "(";
	$queryout .= $lvalue;
        $queryout .= "!=";
	$queryout .= "0";
	$queryout .= ")";
      }
    }

    my $checkstateend = 1;
    while ($checkstateend) {
      # pre-conditions:
      #  for state S_PQUERY:
      #    Next token is '&' or '|', which continues the query,
      #    or next token is ')', which ends this parenthesized query (pop!).
      #  for state S_QUERY:
      #    Next token is '&' or '|', which continues the query,
      #    or there is no following token, which ends the query (pop!).
      my $curstate = $stack[$#stack];
      if ($tokennum < $numtokens) {
	($tokentype, $token) = @{$tokenlist[$tokennum]};
      }
      if ($tokennum >= $numtokens && $curstate == S_PQUERY) {
	my $query = join(" ", map { $_->[1] } @tokenlist);
	print STDERR "End-of-query error; expected more after:\n $query\n";
	exit -1;
      }
      if (($tokennum >= $numtokens && $curstate == S_QUERY) ||
	  ($tokentype == T_CLOSEPAREN && $curstate == S_PQUERY)) {
	# we are finished with a query, so pop the stack
	if ($tokentype == T_CLOSEPAREN && $curstate == S_PQUERY) {
	  # push the close paren out
	  $queryout .= ")";
	  $tokennum++;
	}
	if (@stack == 0) {
	  die "Stack empty!\n";
	}
	pop @stack;
	if (@stack == 0) {
	  if ($tokennum >= $numtokens) { # we're done!
	    $checkstateend = 0;
	  } else {
	    die "Stack empty!\n";
	  }
	}
      } else {
	if ($tokentype == T_AND) {
	  $queryout .= " and ";
	  ($tokennum, $tokentype, $token) = NEXTTOKEN(\@tokenlist, $tokennum);
	} elsif ($tokentype == T_OR) {
	  $queryout .= " or ";
	  ($tokennum, $tokentype, $token) = NEXTTOKEN(\@tokenlist, $tokennum);
	} else {
	  my $querystart = join(" ", map { $_->[1] } @tokenlist[0..$tokennum-1]);
	  my $queryend = join(" ", map { $_->[1] } @tokenlist[$tokennum..$#tokenlist]);
	  print STDERR "Garbage found after:\n $querystart\nhere:\n $queryend\n";
	  exit -1;
	}
	$checkstateend = 0;
      }
    }
  }

  return $queryout;
}


1;
