package NCPS::PowerPoints;

use strict;
use warnings;

use List::Util qw/sum/ ;

use lib '/var/www/html/lib' ;
use NCPS::UTIL qw/prepareExecute reverse_name pretty_time getInfoById/ ;
use NCPS::Teams qw/ getTeamInfo getRoster getBestTimes2 / ;
use NCPS::Meets qw/ getEventLayout getEventLayout2 /;
use NCPS::Entries qw / getEntries getSwimmers / ;
use NCPS::Results qw / getResultDetail getPerformancePoints / ;
use NCPS qw/ debug /;


my $debug = 1 ;
our (@ISA, @EXPORT_OK);

BEGIN {

    require Exporter;
    
    @ISA = qw(Exporter);
    
    @EXPORT_OK = qw/
    addRankingToDB
    getAllPPRankings
    getPPTeams
    getRankingDates
    getTeamPP
    preparePPApp
    getRankings
    getBestRelays
    getTopPerformances
    getBestLineup
/;
}



sub getAllPPRankings {
    # call getTeamPP for all teams in DB
    my ( $date , $dbh ) = @_ ;
    my @teams = ();
    my %power_points = ();
    my $st = "
	SELECT
		distinct team_id
	FROM
		results
	";
    my $sth = prepareExecute( $st , $dbh ) ;
    while ( my $team_id = $sth->fetchrow() ) {
        my $team_info = getTeamInfo( $team_id , $dbh ) ;
        if ( $team_info->{association} eq 'NCHSAA' or $team_info->{association} eq 'NCISAA' ) {
            push @teams , $team_id ;
        }
    }
    foreach my $team_id ( @teams ) {
        $power_points{$team_id}{points}{'M'} = (getTeamPP( $team_id , 'M' , $date , $dbh ))[0] ;
        $power_points{$team_id}{points}{'F'} = (getTeamPP( $team_id , 'F' , $date , $dbh ))[0] ;
        my $team_info = getTeamInfo( $team_id , $dbh ) ;
        $power_points{$team_id}{display} = "$team_info->{nickname} $team_info->{mascot}" ;
    }
    my $power_points = \%power_points ;
    return $power_points ;
}


sub getPPTeams {
    my @team_ids = () ;
    my ( $gender , $dbh ) = @_ ;
    my $st = "
    SELECT
        distinct team_id
    FROM
        rankings
    WHERE
        gender = '$gender'
";
    my $sth = prepareExecute( $st , $dbh ) ;
    while( my $team_id = $sth->fetchrow() ) {
        push @team_ids , $team_id ; 
    }
    my $team_ids = \@team_ids ;
    return $team_ids ;
}

sub getTeamPP {
    
    use Data::Dumper ;
    Data::Dumper::Sortkeys => 1 ;
    Data::Dumper::Indent => 1 ;
    
    use List::Util qw/ max / ;    
    
    my ( $team_id , $gender , $date , $type , $dbh ) = @_ ;

    my $ptiel = 3 ; # 3 individual entries per team ;
    my $ptrel = 2 ; # 2 relays entries per team ;
    
    if ( $type eq 'champs' ) {
        $ptiel = 4 ; # 3 individual entries per team ;
        $ptrel = 1 ; # 2 relays entries per team ;
    } 
    
    my @inputs = ( $team_id , $gender , $date ) ;
    
    my $inputs = Dumper @inputs ;
    ##debug ( $inputs ) ;
    
	use List::Util qw( sum );
	
    my %nisca = () ;
    my @ind_coefficients = () ;
    my @relay_coefficients = () ;

    my $roster = getRoster( $team_id , $gender , $dbh ) ;
    
    my $relays = getBestRelays( $team_id , $gender , $date , $dbh ) ;
    
    my $swimmers = getSwimmers( $team_id , $gender , $date , 'points' , $dbh ) ;
    #debug( Dumper $swimmers ) ; 
    #debug( Dumper $relays ) ;
        
    my $layout_id = 3 ; # regular season meet with diving ( 6 dives )
    my $event_layout = getEventLayout( $layout_id , $dbh ) ;
    
    my %roster = %{$roster} ;
    my %relays = %{$relays} ;
    
    foreach my $event_id ( keys %relays ) {
        foreach my $legs ( keys %{$relays{$event_id}} ) {
            # remove any results from inactive swimmers
            my @legs = split '\|' , $legs ;
            foreach my $leg ( @legs ) {
                if ( $roster{$leg}{active} == 0 ) {
                    $relays{$event_id}{$legs}{points} = 0 ;
                }
            }
            # end removal of inactive swimmers 
            if ( $relays{$event_id}{$legs}{points} == 0 ) {
                delete $relays{$event_id}{$legs} ;
            }
        }
    }
    
    my %swimmers = %{$swimmers} ;
    foreach my $swimmer ( keys %swimmers ) {
        if ( $roster{$swimmer}{active} == 0 ) {
            delete $swimmers{$swimmer} ;
            delete $roster{$swimmer} ;
        }
    }
    
    if ( scalar ( keys %swimmers ) == 0 and scalar ( keys %relays ) == 0 ) {
        return ( 0 ) ;
    }
    
    my @ind_result_ids = ();
    my @rel_result_ids = ();
     
    foreach my $event_num ( keys %{$event_layout->{data}} ) {
        next if ( $event_layout->{data}{$event_num}{gender} ne $gender || $event_layout->{data}{$event_num}{ir_flag} ne 'I' ) ;
        foreach my $athlete_id ( sort { $roster{$a}{flname} cmp $roster{$b}{flname} } keys %roster ) {
            $swimmers{$athlete_id}{points}{$event_layout->{data}{$event_num}{id}} = $swimmers->{$athlete_id}{$event_layout->{data}{$event_num}{id}}{pp} || 0 ;
            if ( $type eq 'champs' ) {
                $swimmers{$athlete_id}{points}{$event_layout->{data}{$event_num}{id}} = $swimmers->{$athlete_id}{$event_layout->{data}{$event_num}{id}}{ncps_points} || 0 ;
            }
            my $event_id = $event_layout->{data}{$event_num}{id} ;
            # address 6/11 dives
            if ( $event_num == 9 || $event_num == 10 ) {
                my $tmp_event_num = $event_num + 16 ;
                my $eleven_dives_result = $swimmers->{$athlete_id}{$tmp_event_num}{result_id} || 0 ;
                my $six_dives_pp        = $swimmers->{$athlete_id}{$event_num}{pp} || 0 ;
                my $eleven_dives_pp     = $swimmers->{$athlete_id}{$tmp_event_num}{pp} || 0 ;
                if ( $eleven_dives_pp > $six_dives_pp ) {
                    $swimmers{$athlete_id}{points}{$event_layout->{data}{$event_num}{id}} = $eleven_dives_pp ;
                    $swimmers{$athlete_id}{$event_num}{result_id} = $eleven_dives_result ;
                }
            }
#if (0) { this is a hack for split times in the 50 free
            if ( $event_num == 7 || $event_num == 8 ) {
                my $tmp_event_num = $event_num + 20 ;
                my $eleven_dives_result = $swimmers->{$athlete_id}{$tmp_event_num}{result_id} || 0 ;
                my $six_dives_pp        = $swimmers->{$athlete_id}{$event_num}{pp} || 0 ;
                my $eleven_dives_pp     = $swimmers->{$athlete_id}{$tmp_event_num}{pp} || 0 ;
                if ( $eleven_dives_pp > $six_dives_pp ) {
                    $swimmers{$athlete_id}{points}{$event_layout->{data}{$event_num}{id}} = $eleven_dives_pp ;
                    $swimmers{$athlete_id}{$event_num}{result_id} = $eleven_dives_result ;
                }
            }
#    }    
#if (0) { this is a hack for split times in the 100 free
            if ( $event_num == 13 || $event_num == 14 ) {
                my $tmp_event_num = $event_num + 16 ;
                my $eleven_dives_result = $swimmers->{$athlete_id}{$tmp_event_num}{result_id} || 0 ;
                my $six_dives_pp        = $swimmers->{$athlete_id}{$event_num}{pp} || 0 ;
                my $eleven_dives_pp     = $swimmers->{$athlete_id}{$tmp_event_num}{pp} || 0 ;
                if ( $eleven_dives_pp > $six_dives_pp ) {
                    $swimmers{$athlete_id}{points}{$event_layout->{data}{$event_num}{id}} = $eleven_dives_pp ;
                    $swimmers{$athlete_id}{$event_num}{result_id} = $eleven_dives_result ;
                }
            }
#    }    
            
        }
    }
            my $tmsg = Dumper $swimmers ;
            #debug( $tmsg ) ;
   
    foreach my $event_id ( keys %relays ) {
        foreach my $legs ( keys %{$relays{$event_id}} ) {
            my @legs = split '\|' , $legs ;
            foreach my $leg ( @legs ) {
                $swimmers{$leg}{relay}{$event_id}{$legs} =  $relays{$event_id}{$legs}{points} ;
            }
        }
    }

    foreach my $athlete_id ( sort { reverse_name( $roster{$a}{flname}) cmp  reverse_name( $roster{$b}{flname}) } keys %roster ) {
        foreach my $event_num ( sort { $a <=> $b } keys %{$event_layout->{data}} ) {
            next if ( $event_layout->{data}{$event_num}{gender} ne $gender || $event_layout->{data}{$event_num}{ir_flag} ne 'I'  ) ;
            push @ind_result_ids , $swimmers{$athlete_id}{$event_num}{result_id} || 0 ; 
            
            push @ind_coefficients , $swimmers{$athlete_id}{points}{$event_layout->{data}{$event_num}{id}} || 0 ;
            
        }
    }
    
    foreach my $athlete_id ( sort { reverse_name($roster{$a}{flname}) cmp reverse_name($roster{$b}{flname}) } keys %roster ) {
        foreach my $event_id ( sort { $a <=> $b } keys %relays ) {
            foreach my $legs ( sort { $a cmp $b } keys %{$relays{$event_id}} ) {
                
                push @relay_coefficients , $swimmers{$athlete_id}{relay}{$event_id}{$legs} || 0 ;
                
                if ( $swimmers{$athlete_id}{relay}{$event_id}{$legs} ) {
                    push @rel_result_ids , $relays{$event_id}{$legs}{result_id}  ;
                } else {
                    push @rel_result_ids , 0 ;
                }
            }
        }
    }
    
    if ( sum( @ind_coefficients, @relay_coefficients ) == 0 ) {
        return ( 0 ) ;
    }
   
    my ($num_r1 , $num_r2 , $num_r3) = map { scalar ( keys %{$relays{$_}} ) }  ( sort { $a <=> $b  } keys %relays ) ;
    ($num_r1 , $num_r2 , $num_r3) = map { $_ || 0 } ($num_r1 , $num_r2 , $num_r3) ;
 
    my $num_swimmers = scalar ( keys %swimmers ) ;
    
    my $num_ind = 9 ; # 9 individual events ;
    my $num_rel = 3 ; # 3 relay events ; 3 ; # 3 relay events ; 3 ; # 3 relay events ; scalar ( keys %relays ) ;
    my $num_rr = $num_r1 + $num_r2 + $num_r3 ; #total number of relay results. 
    
    my $pstel = 4 ; # 4 entries per person ;
    my $psiel = 2 ; # 2 individual entries per person ;
    
    my $ind_coeffs = join ' ' , @ind_coefficients ;
    my $rel_coeffs = join ' ' , @relay_coefficients ;
    my $rel_result_ids = join ' ' , @rel_result_ids ;
    my $ind_result_ids = join ' ' , @ind_result_ids ;
    
    my @mapr = () ;
    
    my @commands = () ;
    #push @commands , "% declare quantities;";
    push @commands , "num_swimmers = $num_swimmers;";
    push @commands , "num_ind = $num_ind;";
    push @commands , "num_rel = $num_rel;";
    push @commands , "num_r1 = $num_r1;";
    push @commands , "num_r2 = $num_r2;";
    push @commands , "num_r3 = $num_r3;";
    push @commands , "num_rr = num_r1 + num_r2 + num_r3;";
    push @commands , "pstel = $pstel;";
    push @commands , "psiel = $psiel;";
    push @commands , "ptiel = $ptiel;";
    push @commands , "ptrel = $ptrel;";
    push @commands , "ind_coeffs = [ $ind_coeffs ];" ;
    push @commands , "rel_coeffs = [ $rel_coeffs ];" ;
    
    if ( scalar @ind_coefficients ) {
    #push @commands , "# 1st Constraint - Per-Swimmer-Total-Event-Limit ;";
    push @commands , "B1 = pstel * ones( $num_swimmers , 1 ) ; " ;
    push @commands , "Ctype1 = char( 'U' * ones( $num_swimmers , 1 ) ); ";
    push @commands , "for i=1:num_swimmers;";
    push @commands , "    A1_temp = zeros( num_swimmers , num_ind + num_rr ) ; " ;
    push @commands , "    A1_temp(i,:) = ones( 1 , num_ind + num_rr ) ; " ;
    push @commands , "    A1(i,:) = reshape( A1_temp' , 1 , num_swimmers * ( num_ind + num_rr ) ) ; " ;
    push @commands , "end;";
    push @mapr , 1 ;
    
    #push @commands , "% 2nd Constraint - Per-Team-Individual-Event-Limit; ";
    push @commands , "B2 = ptiel * ones( num_ind , 1 ) ; ";
    push @commands , "Ctype2 = char( 'U' * ones( num_ind , 1 ) ) ;";
    push @commands , "for i=1:num_ind; ";
    push @commands , "    A2_temp = zeros( num_swimmers , num_ind + num_rr ) ; ";
    push @commands , "    A2_temp(:,i) = ones( num_swimmers , 1 ) ; ";
    push @commands , "    A2(i,:) = reshape( A2_temp' , 1 , num_swimmers * ( num_ind + num_rr ) ) ; " ;
    push @commands , "end;";
    push @mapr , 2 ;
    
    #push @commands , "% 3rd Constraint - Per-Swimmer-Individual-Event-Limit; ";
    push @commands , "B3 = psiel * ones( num_swimmers , 1 ) ;";
    push @commands , "Ctype3 = char( 'U' * ones( num_swimmers , 1 ) ) ;  " ;
    push @commands , "for i=1:num_swimmers;";
    push @commands , "    A3_temp = zeros( num_swimmers , num_ind + num_rr ) ;";
    push @commands , "    A3_temp(i,:) = horzcat( ones( 1 , num_ind ) , zeros( 1 , num_rr ) ) ; " ;
    push @commands , "    A3(i,:) = reshape( A3_temp' , 1 , num_swimmers * ( num_ind + num_rr ) ) ; " ;
    push @commands , "end;";
    push @mapr , 3 ;
    }
    #push @commands , "% 4th Constraint - Per-Team-Relay-Event-Limit (e.g, 2 for dual, 1 for championship); ";
    push @commands , "B4 = 4 * ptrel * ones( num_rel , 1 ) ; " ; 
    push @commands , "B4Z = 4 * ptrel * zeros( num_rel , 1 ) ; " ; # allow no relay entries in a given relay event (20200211 - relaxed constraint that required A AND B)
    push @commands , "A41 = horzcat( zeros( num_swimmers , num_ind ) , ones( num_swimmers , num_r1 ) , zeros( num_swimmers , num_r2 + num_r3 ) ) ; " ;
    push @commands , "A4(1,:) = reshape( A41' , 1 , num_swimmers * ( num_ind + num_rr ) ) ; " ;
    push @commands , "A42 = horzcat( zeros( num_swimmers , num_ind + num_r1 ) , ones( num_swimmers , num_r2 ) , zeros( num_swimmers , num_r3 ) ) ; " ;
    push @commands , "A4(2,:) = reshape( A42' , 1 , num_swimmers * ( num_ind + num_rr ) ) ; " ;
    push @commands , "A43 = horzcat( zeros( num_swimmers , num_ind + num_r1 + num_r2 ) , ones( num_swimmers , num_r3 ) ) ; " ;
    push @commands , "A4(3,:) = reshape( A43' , 1 , num_swimmers * ( num_ind + num_rr ) ) ; " ;
    push @commands , "B4 = [ B4 ; B4Z ];";
    push @commands , "A4 = [ A4 ; A4 ];";
    push @commands , "Ctype4 = [ char( 'U' * ones( num_rel , 1 ) ) ; char( 'L' * ones( num_rel , 1 ) ) ] ; ";
    push @mapr , 4 ;
    
    #push @commands , "% 5th Constraint - (Logical) Swimmer can't be on A and B of same Relay Event.; ";
    push @commands , "B5 = ones( num_rel * num_swimmers , 1 ) ; " ;
    push @commands , "Ctype5 = char( 'U' * ones( num_rel * num_swimmers  , 1 ) ) ; ";
    push @commands , "for i = 1 : num_swimmers ; ";
    push @commands , "    tmp = zeros( num_swimmers , num_ind + num_rr ) ; " ;
    push @commands , "    tmp( i , num_ind+1:num_ind+num_r1 ) = ones( 1 , num_r1 ) ; ";
    push @commands , "    A5new1( i , : ) = reshape ( tmp' , 1 , num_swimmers * ( num_ind + num_rr ) ) ; ";
    push @commands , "end ; ";

    push @commands , "for i = 1 : num_swimmers ;" ;
    push @commands , "    tmp = zeros( num_swimmers , num_ind + num_rr ) ;" ;
    push @commands , "    tmp( i , num_ind+num_r1+1:num_ind+num_r1+num_r2 ) = ones ( 1 , num_r2 ) ;" ;
    push @commands , "    A5new2( i , : ) = reshape ( tmp' , 1 , num_swimmers * ( num_ind + num_rr ) ) ;" ;
    push @commands , "end ;" ;

    push @commands , "for i = 1 : num_swimmers ;" ;
    push @commands , "    tmp = zeros( num_swimmers , num_ind + num_rr ) ;" ;
    push @commands , "    tmp( i , num_ind+num_r1+num_r2+1:num_ind+num_r1+num_r2+num_r3 ) = ones ( 1 , num_r3 ) ;" ;
    push @commands , "    A5new3( i , : ) = reshape ( tmp' , 1 , num_swimmers * ( num_ind + num_rr ) ) ;" ;
    push @commands , "end ;" ;
  
    push @commands , "A5 = [ A5new1 ; A5new2 ; A5new3 ];" ;
    push @mapr , 5 ;

    if ( scalar @relay_coefficients ) {    
    #push @commands , "% 6th Constraint - (Logical) Relay teams have exactly four members; ";
    push @commands , "relay_points = reshape( rel_coeffs' , num_rr , num_swimmers )' ; ";
    push @commands , "idx = ( relay_points > 0 ) ; ";
    push @commands , "B6 = zeros( num_rr , 1 ) ; " ;
    push @commands , "A6temp = zeros( num_swimmers , num_ind + num_rr ) ; ";
    push @commands , "for j = 1 : num_rr; ";
    push @commands , "    temp = [ 1:num_swimmers ]'(idx(:,j)) ; ";
    push @commands , "    A6temp( temp(1) , j + num_ind ) = 3 ; ";
    push @commands , "    for i = 2:size(temp)(1); ";
    push @commands , "        A6temp( temp(i) , num_ind + j ) = -1 ; ";
    push @commands , "    end ";
    push @commands , "end;";
    push @commands , "for i = 1:num_rr; ";
    push @commands , "    A6_ = zeros( num_swimmers , num_ind + num_rr ) ; ";
    push @commands , "    A6_( : , num_ind + i ) = A6temp( : , num_ind + i ) ; ";
    push @commands , "    A6(i,:) = reshape( A6_' , 1 , num_swimmers * ( num_ind + num_rr ) ) ; " ;
    push @commands , "end;";
    push @commands , "A6 = [ A6 ; A6 ] ; ";
    push @commands , "B6 = [ B6 ; B6 ] ; ";
    push @commands , "Ctype6 = [ char( 'U' * ones( num_rr , 1 ) ) ; char( 'L' * ones( num_rr , 1 ) ) ] ; ";
    push @mapr , 6 ;
    }
    #push @commands , "% 7th,8th Constraints - (Logical) Selection coefficients are either 1 or 0; ";
    push @commands , "B7 = ones( num_swimmers * ( num_ind + num_rr ) , 1 ) ;";
    push @commands , "Ctype7 = char( 'U' * ones( num_swimmers * ( num_ind + num_rr ) , 1 ) ) ; ";
    push @commands , "A7 = eye( num_swimmers * ( num_ind + num_rr ) , num_swimmers * ( num_ind + num_rr ) ) ; ";
    push @mapr , 7 ;
    push @commands , "B8 = zeros( num_swimmers * ( num_ind + num_rr ) , 1 ) ; ";
    push @commands , "Ctype8 = char( 'L' * ones( num_swimmers * ( num_ind + num_rr ) , 1 ) ) ; ";
    push @commands , "A8 = eye( num_swimmers * ( num_ind + num_rr ) , num_swimmers * ( num_ind + num_rr ) ) ; ";
    push @mapr , 8 ;
    
    #push @commands , "% Variable is an integer; " ;
    push @commands , "Vtype = char( \"I\" * ones( num_swimmers * ( num_ind + num_rr ) , 1 ) ) ; ";
    push @commands , "sense = -1 ; ";
    #push @commands , "% Bounds; ";
    push @commands , "lb = zeros( num_swimmers * ( num_ind + num_rr ) , 1 ); ";
    push @commands , "ub = Inf * ones( num_swimmers * ( num_ind + num_rr ) , 1 ); ";
    
    #push @commands , "% Combine; ";
    
    my $A = join ' ; ' , map { "A$_" } @mapr ;
    push @commands , "A = [ $A ] ; ";
    
    my $B = join ' ; ' , map { "B$_" } @mapr ;
    push @commands , "B = [ $B ] ; ";
    
    my $Ctype = join ' ; ' , map { "Ctype$_" } @mapr ;
    push @commands , "Ctype = [ $Ctype ] ; ";
    
    my $cprime = '' ;
    if ( scalar @relay_coefficients == 0 )  {
        $cprime = "cprime = reshape( ind_coeffs  , num_ind , num_swimmers )' ;";
    } elsif ( scalar @ind_coefficients == 0 ) {
        $cprime = "cprime = 1/4*reshape( rel_coeffs' , num_rr , num_swimmers )' ; " ;
    } else {
        $cprime = "cprime = horzcat( reshape( ind_coeffs , num_ind , num_swimmers )' , 1/4*reshape( rel_coeffs' , num_rr , num_swimmers )' ) ;";
    }
    
    push @commands , $cprime ;
    push @commands , "c = reshape( cprime' , 1 , num_swimmers * ( num_ind + num_rr ) )  ;";
    push @commands , "[ xopt , zmx ] = glpk( c , A , B , lb , ub , Ctype , Vtype , sense );";
    #push @commands , "if \!( zmx > 0 ) xopt = ( c' > 0 ) ; zmx = sum(c') ; endif ;";
    push @commands , "xopt , zmx" ;
    
	# write HTML to file
	my $docroot = $ENV{DOCUMENT_ROOT} || '/var/www/html/' ;
	if ( substr $docroot , -1 ne '/' ) {
    	$docroot = "$docroot/" ;
	}
	my $team_info = getTeamInfo( $team_id , $dbh ) ;
	my $filetitle = $team_info->{nickname} . "_$gender" ;
	$filetitle =~ s/ /_/g ;
	$filetitle =~ s/[\(\)]//g ;
	my $filename = "${docroot}docs/pp_octave_${filetitle}.m" ;
	my $fileout  = "${docroot}docs/pp_octave_${filetitle}.out" ;
	debug ( $filename );
    chomp( $filename );
	open(my $fh, ">", $filename ) or die "cannot open > $filename for output: $!" ;
    foreach ( @commands ) {
        print $fh $_ ;
    }
	close $fh ;
	my $return = `octave -q $filename > $fileout` ;

	open( $fh, "<", $fileout ) or die "Can't open file $fileout for input: $!";
	my $output = do { local $/; <$fh> };
    
    $output =~ s/(\d)\n/$1/g;
    $output =~ s/(xopt =)\s+(0|1)/$1 $2/s;
    $output =~ m/xopt =(.*?)zmx =(.*?)/s;
    my $xopt = $1;
    chomp $xopt ;
    my $idx = index $output , "zmx =" ;
    my $power_points = substr $output , $idx + 5 ;
    $power_points =~ s/^\s+|\s+$//g ; 
    #debug( $power_points ) ;
    if ( $power_points eq "NA" ) {
        return ( 0 ) ;
    }
    
    @commands = () ;
    push @commands , "num_swimmers = $num_swimmers;";
    push @commands , "num_ind = $num_ind;";
    push @commands , "num_rel = $num_rel;";
    push @commands , "num_r1 = $num_r1;";
    push @commands , "num_r2 = $num_r2;";
    push @commands , "num_r3 = $num_r3;";
    push @commands , "num_rr = num_r1 + num_r2 + num_r3;";
    push @commands , "ind_coeffs = [ $ind_coeffs ];" ;
    push @commands , "rel_coeffs = [ $rel_coeffs ];" ;
    push @commands , "ind_result_ids = [ $ind_result_ids ];";
    push @commands , "rel_result_ids = [ $rel_result_ids ];";
    
    my $rprime = '' ; # rprime is made of powerpoints
    my $idprime = '' ;
    if ( scalar @relay_coefficients == 0 )  {
        #debug( "No relay coefficients" ) ;
        $rprime = "rprime = reshape( ind_coeffs , num_ind , num_swimmers )' ;";
        $idprime = "idprime = reshape( ind_result_ids , num_ind , num_swimmers )' ;" ;
    } elsif ( scalar @ind_coefficients == 0 ) {
        #debug( "No individual coefficients" ) ;
        $rprime = "rprime = 1/4*reshape( rel_coeffs' , num_rr , num_swimmers )' ; " ;
        $idprime = "idprime = reshape( rel_result_ids' , num_rr , num_swimmers )' ; " ;
    } else {
        #debug( "Both Individual and Relay Coefficients present" ) ;
        $rprime = "rprime = horzcat( reshape( ind_coeffs , num_ind , num_swimmers )' , 1/4*reshape( rel_coeffs' , num_rr , num_swimmers )' ) ;";
        $idprime = "idprime = horzcat( reshape( ind_result_ids , num_ind , num_swimmers )' , reshape( rel_result_ids' , num_rr , num_swimmers )' ) ;" ;
    }

    push @commands , $rprime ;
    push @commands , $idprime ;
    push @commands , "r = reshape( rprime' , 1 , num_swimmers * ( num_ind + num_rr ) )  ;";
    push @commands , "xopt = [ $xopt ] ;";
    push @commands , "unique(idprime'(xopt > 0))'";
    
	$filename = "${docroot}docs/pp_octave_${filetitle}_2.m" ;
	$fileout  = "${docroot}docs/pp_octave_${filetitle}_2.out" ;
	debug ( $filename );
    chomp( $filename );
	open($fh, ">", $filename ) or die "cannot open > $filename for output: $!" ;
    foreach ( @commands ) {
        print $fh $_ ;
    }
	close $fh ;
	$return = `octave -q $filename > $fileout` ;

	open($fh, "<", $fileout ) or die "Can't open file $fileout for input: $!";
	$output = do { local $/; <$fh> };
    
    my $results_to_use = (split '=' , $output)[1] ;
    my @results_to_use = split ' ' , $results_to_use ;
    
    use Data::Dumper ;
    my $dmsg = Dumper @results_to_use ;
    use NCPS::Events qw/ getEventInfo / ;
    debug( "Results to use: $dmsg" ) ;
    foreach my $result_id ( @results_to_use ) {
        my ( $athlete_id , $event_id , $legs , $time , $points ) = ( 0 , 0 , '' , 0 , 0 ) ;
        if ( $result_id > 0 ) {
            #debug( "Detail for result: $result_id" ) ;
            ( $athlete_id , $event_id , $legs , $time , $points ) = getResultDetail( $result_id , $dbh ) ;
            #debug( $event_id ) ; 
            my $event_info = getEventInfo( $event_id , $dbh ) ;
            if ( $event_id == 27 || $event_id == 28 || $event_id == 29 || $event_id == 30 ) {
                $event_id = $event_info->{reference_event} ;
            }
            #debug( "irflag: $event_layout->{data}{$event_id}{ir_flag}" ) ;
            #if ( exists ( $event_layout->{data}{$event_id}{ir_flag} ) ) { #this throws a warning about uninitialized something-or-other, but this if loop breaks 11 dives.
                if ( $event_layout->{data}{$event_id}{ir_flag} eq 'R' ) {
                    push @{$nisca{$event_id}} , [ $legs , $time , $points ] ;
                } else {
                    push @{$nisca{$event_id}} , [ $athlete_id , $time , $points ] ;
                }
            #}
        } else { debug( "nothing to do here. " . ref $result_id ) ; } 
    }

	my $nisca = \%nisca ;
	$dmsg = Dumper $event_layout ;
	#debug ( $dmsg ) ;
	$roster = \%roster ;
	$dmsg = Dumper $roster ;
	#debug ( $dmsg ) ;
	return ( $power_points , $nisca , $event_layout , $roster ) ;
}

sub addRankingToDB {
    my ( $team_id , $date , $gender , $points , $dbh ) = @_ ;
    my $st = "
    SELECT
        count(*)
    FROM
        rankings
    WHERE
        team_id = $team_id
        AND
        gender = '$gender'
        AND
        ranking_date = '$date'
    ";
    my $sth = prepareExecute( $st , $dbh ) ;
    my $count = $sth->fetchrow() ;
    $sth->finish() ;
    if ( $count ) {
        $st = "
    UPDATE
        rankings
    SET
        power_points = $points
    WHERE
        team_id = $team_id
        AND
        gender = '$gender'
        AND
        ranking_date = '$date'
    ";
        $sth = prepareExecute( $st , $dbh ) ;
        $sth->finish();
    } else {
        $st = "
    INSERT INTO
        rankings
    (
        ranking_date,
        team_id,
        gender,
        power_points
    ) 
    VALUES
    (
        '$date',
        $team_id,
        '$gender',
        $points
    )
    ";
        $sth = prepareExecute( $st , $dbh ) ;
        $sth->finish() ;
    }       
}

sub getRankingDates {
    my $dbh = shift ;
    my @dates = () ;
    my $st = "
    SELECT
        distinct ranking_date
    FROM
        rankings
    ORDER BY
        ranking_date ASC
    ";
    my $sth = prepareExecute( $st , $dbh ) ;
    while ( my $date = $sth->fetchrow() ) {
        push @dates , $date ;
    }
    my $dates = \@dates ;
    return $dates ;
}

sub preparePPApp {
    my ( $team_id , $gender , $date , $dbh ) = @_ ;
    # retrive the PP information
    my ( $power_points , $nisca , $event_layout , $roster ) = getBestLineup( $team_id , $gender , $date , 'nisca' , $dbh ) ;
    #my ( $power_points , $nisca , $event_layout , $roster ) = getTeamPP( $team_id , $gender , $date , 'nisca' , $dbh ) ;

    if ( $power_points == 0 ) {
        return "No application possible - No points scored" ;
    }
    
    my %nisca = %{$nisca} ;
    my $dbhms = Dumper %nisca ;
    #debug( $dbhms )  ;
    my %roster = %{$roster} ;
    # move 11 meter diving results to event_key for 6 meter diving.
    # event keys are 25 and 26 ;
    if ( scalar $nisca{25} ) {
        foreach ( @{$nisca{25}} ) {
            push @{$_} , "(11D)" ;
        }
        push @{$nisca{9}} , @{$nisca{25}} ;
    }

    if ( scalar $nisca{26} ) {
        foreach ( @{$nisca{26}} ) {
            push @{$_} , "(11D)" ;
        }
        push @{$nisca{10}} , @{$nisca{26}} ;
    }

    # create the HTML document
    my @lines = () ;
	push @lines , "<html>" ;
	push @lines , "<style>" ;
	push @lines , "td { border: 1px solid black; }" ;
	push @lines , "th { border: 1px solid black; }" ;
	push @lines , "</style>" ;
	
	push @lines , "<table style='border-collapse:collapse; font-size:17px; font-family:sans-serif; width:6in; height:7in;'>" ;
	push @lines , "    <tr>" ;
	push @lines , "        <th colspan = '2' style='width:16%'>EVENT</th>" ;
	push @lines , "        <th colspan = '2' style='width:52%'>NAMES</th>" ;
	push @lines , "        <th style='width:5%'>GR</th>" ;
	push @lines , "        <th style='width:14%'>TIME</th>" ;
	push @lines , "        <th style='width:13%'>PTS</th>" ;
	push @lines , "    </tr>" ;
	foreach my $event_num ( sort { $a <=> $b } keys %{$event_layout->{data}} ) {
	    next if ( $event_layout->{data}{$event_num}{gender} ne $gender ) ;
	    my $display = $event_layout->{data}{$event_num}{pp_display} ;
	    if ( $event_layout->{data}{$event_num}{ir_flag} eq 'R' ) {
            my $do_once = 1 ;
	        foreach ( sort { $nisca{$event_num}[$b][2] <=> $nisca{$event_num}[$a][2] } ( 0 , 1 )) {
				my $rel_deg = '';
	            my $legs = $nisca{$event_num}[$_][0] ;
                my $time = $nisca{$event_num}[$_][1] ;
                if ( $event_layout->{data}{$event_num}{sd_flag} eq 'D' ) { $time = sprintf "%.2f" , $time ; }
                else { $time = pretty_time( $time ) ; }
#	            my $time = pretty_time( $nisca{$event_num}[$_][1] ) unless ( $event_layout->{data}{$event_num}{sd_flag} eq 'D' ) ;
	            my $points = $nisca{$event_num}[$_][2] ;
	            my @legs = split '\|' , $legs ;
	            @legs = map { $roster{$_}{flname} } @legs ;
	            foreach my $lidx ( 0..$#legs ) {
	                my $idx = index $legs[$lidx] , ' ' ; 
	                $legs[$lidx] = substr( $legs[$lidx] , 0 , 1 ) . "." . substr( $legs[$lidx] , $idx ) ;
	            }
                my $leg1 = $legs[0] || '&nbsp;' ;
                my $leg2 = $legs[1] || '&nbsp;' ;
                my $leg3 = $legs[2] || '&nbsp;' ;
                my $leg4 = $legs[3] || '&nbsp;' ;
				push @lines , "    <tr>" ;
	            if ( $do_once ) {
                    $do_once = 0 ;
	    		push @lines , "        <td rowspan = '4' style='padding-left:0.25em'><strong>$display</strong></td>" ;
					$rel_deg = 'A';
	            } else { $rel_deg = 'B'; }
				push @lines , "        <td rowspan = '2'><strong>$rel_deg</strong></td>" ;
				push @lines , "        <td style='padding-left:0.5em;'>$leg1</td>" ;
				push @lines , "        <td style='padding-left:0.5em;'>$leg2</td>" ;
				push @lines , "        <td>    </td>" ;
				push @lines , "        <td rowspan = '2' style='text-align:right; padding-right:0.5em;'>$time</td>" ;
				push @lines , "        <td rowspan = '2' style='text-align:right; padding-right:1em;'>$points</td>" ;
				push @lines , "    </tr>" ;
				push @lines , "    <tr>" ;
				push @lines , "        <td style='padding-left:0.5em;'>$leg3</td>" ;
				push @lines , "        <td style='padding-left:0.5em;'>$leg4</td>" ;
				push @lines , "        <td>    </td>" ;
				push @lines , "    </tr>" ;
	       }
		} else {
	    	my $do_once = 1 ;
	        foreach ( sort { $nisca{$event_num}[$b][2] <=> $nisca{$event_num}[$a][2]  } 0..2) {
	            my $athlete = $roster{$nisca{$event_num}[$_][0]}{flname} || '&nbsp;' ;
	            my $year = $roster{$nisca{$event_num}[$_][0]}{year} ;
                my $time = $nisca{$event_num}[$_][1] ;
	            $time = pretty_time( $time ) unless ( $event_layout->{data}{$event_num}{sd_flag} eq 'D' ) ;
	            my $points = $nisca{$event_num}[$_][2] ;
               my $label = $nisca{$event_num}[$_][3] || '';
               $label = "(6D)" if ( $label eq '' && $event_layout->{data}{$event_num}{sd_flag} eq 'D' && $points > 0 ) ;
				push @lines , "    <tr>" ;
	            if ( $do_once ) {
					push @lines , "        <td rowspan = '3' colspan = '2' style='padding-left:0.25em'><strong>$display</strong></td>" ;
	                $do_once = 0 ;
	            }
				push @lines , "        <td colspan = '2' style='padding-left:0.5em; height:15px;'>$athlete $label</td>" ;
				push @lines , "        <td style='text-align:center;'>$year</td>" ;
				push @lines , "        <td style='text-align:right; padding-right:0.5em;'>$time</td>" ;
				push @lines , "        <td style='text-align:right; padding-right:1em;'>$points</td>" ;
				push @lines , "    </tr>" ;
	        }
		}
	}
	push @lines , "    <tr>" ;
	push @lines , "        <td colspan='3' style='border:none'></td>" ;
	push @lines , "        <td colspan='3' style='border:none; text-align:right; padding-right: 1em; font-weight:bold'>Power Point Total</td>" ;
	push @lines , "        <td style='text-align:right; padding-right:1em; font-weight:bold'>$power_points</td>" ;
	push @lines , "    </tr>" ;
	push @lines , "</table>" ;
	push @lines , "</html>" ;

	# write HTML to file
	my $docroot = $ENV{DOCUMENT_ROOT} || '/var/www/html/' ;
	if ( substr $docroot , -1 ne '/' ) {
    	$docroot = "$docroot/" ;
	}
	my $team_info = getTeamInfo( $team_id , $dbh ) ;
	my $filetitle = $team_info->{nickname} . "_$gender" ;
	$filetitle =~ s/ /_/g ;
	my $filename = "${docroot}docs/pp_apps/${filetitle}.htm" ;
	debug ( $filename );
    chomp( $filename );
	my $pngfile = $filename ;
	$pngfile =~ s/htm$/png/;
    chomp( $pngfile );
	my $pdffile = $filename ;
	$pdffile =~ s/htm$/pdf/;
    chomp( $pdffile );
	open(my $fh, ">", $filename ) or die "cannot open > $filename: $!" ;
    foreach ( @lines ) {
        print $fh $_ ;
    }
	close $fh ;
    # Convert HTML to png
    my @commands = ("/var/www/wkhtmltox/bin/wkhtmltoimage", "--crop-w 640" , "--format png" ,  "--quality 100" ,  $filename , $pngfile ) ;
	my $command = join ' ' , @commands ;
	my $output = `$command` ;
    # Scale png
    @commands = ("/usr/bin/convert" , $pngfile , "-resize 230%" ,  $pngfile ) ;
    $command = join ' ' , @commands ;
    $output = `$command` ;
    # Composite images
    $command = "/usr/bin/composite -gravity SouthWest -geometry +50-0 $pngfile ${docroot}docs/pp_apps/resource/PowerPointApp09_10_Part1.png  ${docroot}docs/pp_apps/${filetitle}_page1.png" ;
    $output = `$command` ;
    # Add page 2
    $command = "/usr/bin/convert ${docroot}docs/pp_apps/${filetitle}_page1.png ${docroot}docs/pp_apps/resource/PowerPointApp18_19_Part2.png $pdffile";
    $output = `$command` ;
    # return link
	$pdffile = "/docs/pp_apps/${filetitle}.pdf" ;
    return $pdffile ;
}

sub getRankings {

    my ( $ranking_date , $limit , $dbh ) = @_ ;
    my %rankings = () ;
    
    my $st = "
SELECT 
    team_id, 
    nickname,
    classification,
    rankings.gender, 
    power_points 
FROM 
    rankings 
    JOIN 
    teams 
    ON 
    rankings.team_id = teams.id 
WHERE 
    ranking_date = '$ranking_date'
    and
    association in ( 'NCHSAA' , 'NCISAA' ) 
ORDER BY
    classification ,
    gender ,
    power_points DESC 
";
    my $count = 0 ;
    my $sth = prepareExecute( $st , $dbh ) ;
    while ( my @data = $sth->fetchrow() ) {
        my ( $team_id , $nickname , $classification, $gender , $power_points ) = @data;
        $count = scalar (keys %{$rankings{$gender}{$classification}} ) + 1 ;
#        if ( $count > $limit && $rankings{$gender}{$count-1}{power_points} != $power_points ) { 
#            next ; 
#        } else {
    
            $rankings{$gender}{$classification}{$count}{team_id} = $team_id ;
            $rankings{$gender}{$classification}{$count}{nickname} = $nickname ;
            $rankings{$gender}{$classification}{$count}{power_points} = $power_points ;   
             
#        }
    }
    
    $sth->finish();
    
    my $rankings = \%rankings;
    return $rankings ;
}

sub getBestRelays {
    my ( $team_id , $gender , $date , $dbh ) = @_ ;
    my $st = "
    SELECT
    q4.result_id,
    q3.event_id, 
    q3.legs, 
    q3.time
FROM
    (SELECT
        q2.event_id,
        q2.legs,
        q2.time
    FROM
        (SELECT
            q1.event_id,
            q1.legs,
            min(q1.time) as time
        FROM
            (SELECT
                results.id as result_id,
                results.event_id,
                results.time,
                group_concat( convert( relays.athlete_id , char(8) ) order by relays.athlete_id separator '|' ) as legs
            FROM
                results
                JOIN
                relays
                ON
                ( results.id = relays.result_id )
            WHERE
                results.team_id = $team_id
                AND
                results.DQ = 'N'
                AND
                results.power_points > 0  
            GROUP BY
                result_id
            ) as q1
        GROUP BY
            event_id,
            legs
        ) as q2
    GROUP BY
        event_id,
        legs
    ORDER BY
        event_id,
        legs
    ) as q3
JOIN
    (SELECT
        results.id as result_id,
        results.event_id,
        results.time,
        group_concat( convert( relays.athlete_id , char(8) ) order by relays.athlete_id separator '|' ) as legs
    FROM
        results
        JOIN
        relays
        ON
        ( results.id = relays.result_id )
    WHERE
        team_id = $team_id
        AND
        DQ = 'N'
        AND
        power_points > 0
    GROUP BY
        result_id
    ) as q4
ON
    q4.time = q3.time
    AND
    q4.event_id = q3.event_id
    AND
    q4.legs = q3.legs
JOIN
    events
ON
    events.id = q4.event_id
WHERE
    gender = '$gender'
    and events.id in ( 1 , 2, 17 , 18 , 23 , 24 ) 
ORDER BY
    event_id,
    legs    
";

    my $sth = prepareExecute( $st , $dbh ) ;

    my %relays = () ;
    
    my $year = 1900 + (localtime)[5];
    my $freshman_year = $year + 3 ;

    while ( my @data = $sth->fetchrow() ) {
        my $skip = 0 ;
        my ( $result_id , $event_id , $legs , $time , $points , $ncps_points ) = () ;
        ( $result_id , $event_id , $legs , $time ) = @data ;
        $points = getPerformancePoints( $event_id , $time , $dbh ) ;
        $ncps_points = getPerformancePoints( $event_id , $time , 'ncps' , $dbh ) ;
        
        my @legs = split '\|' , $legs ;
        foreach my $athlete_id ( @legs ) {
            my $athlete_info = getInfoById( 'athletes' , $athlete_id , $dbh ) ;
            my $graduation_year = $athlete_info->{graduation_year} || 0 ;
            $skip = 1 if ( $graduation_year > $freshman_year ) ;
        }
        
        next if ( $skip ) ;
        $relays{$event_id}{$legs}{time} = $time ;
        $relays{$event_id}{$legs}{pp} = $points ;
        $relays{$event_id}{$legs}{ncps_points} = $ncps_points ;
        $relays{$event_id}{$legs}{result_id} = $result_id ;
    }

    my $relays = \%relays ;
    use Data::Dumper ; 
    my $msg = Dumper %relays ;
    ##debug ( $msg ) ;
    return $relays ;

}

sub getTopPerformances {
    my ( $gender, $start_date , $dbh ) = @_ ;
    
    my %genders = (
       "F" => "FEMALE" ,
       "M" => "MALE" ,
    ); 
    
    my $st = "SELECT 
    '$genders{$gender}' as gender,
    r.athlete_id, 
    t.name as team_name,
    t.classification,
    a.first,
    a.last,
    r.meet_id, 
    m.date,
    sum(r.power_points) AS power_points 
FROM 
    results r
    LEFT JOIN
    athletes a
    ON
    r.athlete_id = a.id
    LEFT JOIN
    teams t
    ON
    r.team_id = t.id
    LEFT JOIN
    meets m
    ON
    r.meet_id = m.id
WHERE
    a.gender = '$gender'
    and
    m.date >= '$start_date' and m.date < date_add( '$start_date',  INTERVAL 1 WEEK )
    and
    r.power_points > 0
    and
    time > 0
    and 
    m.sub_meet = 0 
    and
    r.event_id < 27
    and
    r.dq = 'N'
    and
    r.split = 'N'
    and
    r.exh = 'N'
    and
    m.event_layout2 in ( 1 ,2 ,3 , 7, 8, 9 ) 
GROUP BY
    r.meet_id,
    r.athlete_id,
    t.classification
ORDER BY
    (9) DESC
";

my @results = () ;
my $sth = prepareExecute( $st , $dbh ) ;
while ( my @data = $sth->fetchrow() ) {
    push @results , \@data ;
}

$sth->finish() ;
return \@results ; 

}

sub getBestLineup {
    use Data::Dumper ;
    Data::Dumper::Sortkeys => 1 ;
    Data::Dumper::Indent => 1 ;
    
    use List::Util qw/ max / ;    
    
    my ( $team_id , $gender , $date , $type , $dbh ) = @_ ;

    my $ptiel = 3 ; # 3 individual entries per team ;
    my $ptrel = 2 ; # 2 relays entries per team ;
    my $points_schema = 'pp' ;
    
    if ( $type eq 'champs' ) {
        $ptiel = 4 ; # 3 individual entries per team ;
        $ptrel = 1 ; # 2 relays entries per team ;
        $points_schema = 'ncps_points' ;
    } 
    
    my @inputs = ( $team_id , $gender , $date ) ;
    
    my $inputs = Dumper @inputs ;
    ##debug ( $inputs ) ;
    
	use List::Util qw( sum );
	
    my %nisca = () ;
    my @ind_coefficients = () ;
    my @relay_coefficients = () ;

    my $roster = getRoster( $team_id , $gender , $dbh ) ;
    
    my $relays = getBestRelays( $team_id , $gender , $date , $dbh ) ;
    
    my $best_times = getBestTimes2( $team_id , $gender , $type , $dbh ) ;
    my %best_times = %{$best_times} ;
    
    my $layout_id = 3 ; # event_layouts2 "Regular Season Meet 6 Dives, Yards Pool"
    my $event_layout = getEventLayout( $layout_id , $dbh ) ;

    my %roster = %{$roster} ;
    my %relays = %{$relays} ;
    
    if ( scalar ( keys %best_times ) == 0 and scalar ( keys %relays ) == 0 ) {
        return ( 0 ) ;
    }
    
    my @ind_result_ids = ();
    my @rel_result_ids = ();

    foreach my $event_id ( keys %relays ) {
        foreach my $legs ( keys %{$relays{$event_id}} ) {
            my @legs = split '\|' , $legs ;
            foreach my $leg ( @legs ) {
                $best_times{$leg}{relay}{$event_id}{$legs} =  $relays{$event_id}{$legs}{$points_schema} ;
            }
        }
    }
        
    print Dumper $best_times ;
    
    my %dive_events = ( );
    $dive_events{"F"}{6}  = 9 ;
    $dive_events{"M"}{6}  = 10 ;
    $dive_events{"F"}{11} = 25 ;
    $dive_events{"M"}{11} = 26 ;
    
    foreach my $athlete_id ( keys %best_times ) {
        my $eleven_dives_result = $best_times{$athlete_id}{times}{$dive_events{$gender}{11}}{result_id} || 0 ;
        my $eleven_dives_points = $best_times{$athlete_id}{times}{$dive_events{$gender}{11}}{$points_schema} || 0 ;
        
        my $six_dives_result = $best_times{$athlete_id}{times}{$dive_events{$gender}{6}}{result_id} || 0 ;
        my $six_dives_points = $best_times{$athlete_id}{times}{$dive_events{$gender}{6}}{$points_schema} || 0 ;
        
        if ( $eleven_dives_points > $six_dives_points ) {
            #print Dumper $best_times{$athlete_id}{times} ;
            $best_times{$athlete_id}{times}{$dive_events{$gender}{6}}{result_id} = $best_times{$athlete_id}{times}{$dive_events{$gender}{11}}{result_id} ;
            $best_times{$athlete_id}{times}{$dive_events{$gender}{6}}{meet_id}   = $best_times{$athlete_id}{times}{$dive_events{$gender}{11}}{meet_id} ;
            $best_times{$athlete_id}{times}{$dive_events{$gender}{6}}{$points_schema}        = $best_times{$athlete_id}{times}{$dive_events{$gender}{11}}{$points_schema} ;
        }
    }

    foreach my $athlete_id ( sort { $best_times{$a}{meta}{sort_name} cmp $best_times{$b}{meta}{sort_name} } keys %best_times ) {
        foreach my $event_id ( 3..16,19..22 ) {
            my $event_info = getInfoById( 'events' , $event_id , $dbh ) ;
            next if ( $event_info->{gender} ne $gender ) ;
            push @ind_result_ids , $best_times{$athlete_id}{times}{$event_id}{result_id} || 0 ; 
            
            push @ind_coefficients , $best_times{$athlete_id}{times}{$event_id}{$points_schema} || 0 ;
            
        }
    }
    
    foreach my $athlete_id ( sort { $best_times{$a}{meta}{sort_name} cmp $best_times{$b}{meta}{sort_name} } keys %best_times ) {
        foreach my $event_id ( sort { $a <=> $b } keys %relays ) {
            foreach my $legs ( sort { $a cmp $b } keys %{$relays{$event_id}} ) {
                
                push @relay_coefficients , $best_times{$athlete_id}{relay}{$event_id}{$legs} || 0 ;
                
                if ( $best_times{$athlete_id}{relay}{$event_id}{$legs} ) {
                    push @rel_result_ids , $relays{$event_id}{$legs}{result_id}  ;
                } else {
                    push @rel_result_ids , 0 ;
                }
            }
        }
    } 

    if ( sum( @ind_coefficients, @relay_coefficients ) == 0 ) {
        return ( 0 ) ;
    }
   
    my ($num_r1 , $num_r2 , $num_r3) = map { scalar ( keys %{$relays{$_}} ) }  ( sort { $a <=> $b  } keys %relays ) ;
    ($num_r1 , $num_r2 , $num_r3) = map { $_ || 0 } ($num_r1 , $num_r2 , $num_r3) ;
 
    my $num_swimmers = scalar ( keys %best_times ) ;
    
    my $num_ind = 9 ; # 9 individual events ;
    my $num_rel = 3 ; # 3 relay events ; 3 ; # 3 relay events ; 3 ; # 3 relay events ; scalar ( keys %relays ) ;
    my $num_rr = $num_r1 + $num_r2 + $num_r3 ; #total number of relay results. 
    
    my $pstel = 4 ; # 4 entries per person ;
    my $psiel = 2 ; # 2 individual entries per person ;
    
    my $ind_coeffs = join ' ' , @ind_coefficients ;
    my $rel_coeffs = join ' ' , @relay_coefficients ;
    my $rel_result_ids = join ' ' , @rel_result_ids ;
    my $ind_result_ids = join ' ' , @ind_result_ids ;
    
    my @mapr = () ;
    
    my @commands = () ;
    push @commands , "% declare quantities;";
    push @commands , "num_swimmers = $num_swimmers;";
    push @commands , "num_ind = $num_ind;";
    push @commands , "num_rel = $num_rel;";
    push @commands , "num_r1 = $num_r1;";
    push @commands , "num_r2 = $num_r2;";
    push @commands , "num_r3 = $num_r3;";
    push @commands , "num_rr = num_r1 + num_r2 + num_r3;";
    push @commands , "pstel = $pstel;";
    push @commands , "psiel = $psiel;";
    push @commands , "ptiel = $ptiel;";
    push @commands , "ptrel = $ptrel;";
    push @commands , "ind_coeffs = [ $ind_coeffs ];" ;
    push @commands , "rel_coeffs = [ $rel_coeffs ];" ;
    
    if ( scalar @ind_coefficients ) {
    push @commands , "% 1st Constraint - Per-Swimmer-Total-Event-Limit ;";
    push @commands , "B1 = pstel * ones( $num_swimmers , 1 ) ; " ;
    push @commands , "Ctype1 = char( 'U' * ones( $num_swimmers , 1 ) ); ";
    push @commands , "for i=1:num_swimmers;";
    push @commands , "    A1_temp = zeros( num_swimmers , num_ind + num_rr ) ; " ;
    push @commands , "    A1_temp(i,:) = ones( 1 , num_ind + num_rr ) ; " ;
    push @commands , "    A1(i,:) = reshape( A1_temp' , 1 , num_swimmers * ( num_ind + num_rr ) ) ; " ;
    push @commands , "end;";
    push @mapr , 1 ;
    
    push @commands , "% 2nd Constraint - Per-Team-Individual-Event-Limit; ";
    push @commands , "B2 = ptiel * ones( num_ind , 1 ) ; ";
    push @commands , "Ctype2 = char( 'U' * ones( num_ind , 1 ) ) ;";
    push @commands , "for i=1:num_ind; ";
    push @commands , "    A2_temp = zeros( num_swimmers , num_ind + num_rr ) ; ";
    push @commands , "    A2_temp(:,i) = ones( num_swimmers , 1 ) ; ";
    push @commands , "    A2(i,:) = reshape( A2_temp' , 1 , num_swimmers * ( num_ind + num_rr ) ) ; " ;
    push @commands , "end;";
    push @mapr , 2 ;
    
    push @commands , "% 3rd Constraint - Per-Swimmer-Individual-Event-Limit; ";
    push @commands , "B3 = psiel * ones( num_swimmers , 1 ) ;";
    push @commands , "Ctype3 = char( 'U' * ones( num_swimmers , 1 ) ) ;  " ;
    push @commands , "for i=1:num_swimmers;";
    push @commands , "    A3_temp = zeros( num_swimmers , num_ind + num_rr ) ;";
    push @commands , "    A3_temp(i,:) = horzcat( ones( 1 , num_ind ) , zeros( 1 , num_rr ) ) ; " ;
    push @commands , "    A3(i,:) = reshape( A3_temp' , 1 , num_swimmers * ( num_ind + num_rr ) ) ; " ;
    push @commands , "end;";
    push @mapr , 3 ;
    }
    push @commands , "% 4th Constraint - Per-Team-Relay-Event-Limit (e.g, 2 for dual, 1 for championship); ";
    push @commands , "B4 = 4 * ptrel * ones( num_rel , 1 ) ; " ; 
    push @commands , "B4Z = 4 * ptrel * zeros( num_rel , 1 ) ; " ; # allow no relay entries in a given relay event (20200211 - relaxed constraint that required A AND B)
    push @commands , "A41 = horzcat( zeros( num_swimmers , num_ind ) , ones( num_swimmers , num_r1 ) , zeros( num_swimmers , num_r2 + num_r3 ) ) ; " ;
    push @commands , "A4(1,:) = reshape( A41' , 1 , num_swimmers * ( num_ind + num_rr ) ) ; " ;
    push @commands , "A42 = horzcat( zeros( num_swimmers , num_ind + num_r1 ) , ones( num_swimmers , num_r2 ) , zeros( num_swimmers , num_r3 ) ) ; " ;
    push @commands , "A4(2,:) = reshape( A42' , 1 , num_swimmers * ( num_ind + num_rr ) ) ; " ;
    push @commands , "A43 = horzcat( zeros( num_swimmers , num_ind + num_r1 + num_r2 ) , ones( num_swimmers , num_r3 ) ) ; " ;
    push @commands , "A4(3,:) = reshape( A43' , 1 , num_swimmers * ( num_ind + num_rr ) ) ; " ;
    push @commands , "B4 = [ B4 ; B4Z ];";
    push @commands , "A4 = [ A4 ; A4 ];";
    push @commands , "Ctype4 = [ char( 'U' * ones( num_rel , 1 ) ) ; char( 'L' * ones( num_rel , 1 ) ) ] ; ";
    push @mapr , 4 ;
    
    push @commands , "% 5th Constraint - (Logical) Swimmer can't be on A and B of same Relay Event.; ";
    push @commands , "B5 = ones( num_rel * num_swimmers , 1 ) ; " ;
    push @commands , "Ctype5 = char( 'U' * ones( num_rel * num_swimmers  , 1 ) ) ; ";
    push @commands , "for i = 1 : num_swimmers ; ";
    push @commands , "    tmp = zeros( num_swimmers , num_ind + num_rr ) ; " ;
    push @commands , "    tmp( i , num_ind+1:num_ind+num_r1 ) = ones( 1 , num_r1 ) ; ";
    push @commands , "    A5new1( i , : ) = reshape ( tmp' , 1 , num_swimmers * ( num_ind + num_rr ) ) ; ";
    push @commands , "end ; ";

    push @commands , "for i = 1 : num_swimmers ;" ;
    push @commands , "    tmp = zeros( num_swimmers , num_ind + num_rr ) ;" ;
    push @commands , "    tmp( i , num_ind+num_r1+1:num_ind+num_r1+num_r2 ) = ones ( 1 , num_r2 ) ;" ;
    push @commands , "    A5new2( i , : ) = reshape ( tmp' , 1 , num_swimmers * ( num_ind + num_rr ) ) ;" ;
    push @commands , "end ;" ;

    push @commands , "for i = 1 : num_swimmers ;" ;
    push @commands , "    tmp = zeros( num_swimmers , num_ind + num_rr ) ;" ;
    push @commands , "    tmp( i , num_ind+num_r1+num_r2+1:num_ind+num_r1+num_r2+num_r3 ) = ones ( 1 , num_r3 ) ;" ;
    push @commands , "    A5new3( i , : ) = reshape ( tmp' , 1 , num_swimmers * ( num_ind + num_rr ) ) ;" ;
    push @commands , "end ;" ;
  
    push @commands , "A5 = [ A5new1 ; A5new2 ; A5new3 ];" ;
    push @mapr , 5 ;

    if ( scalar @relay_coefficients ) {    
    push @commands , "% 6th Constraint - (Logical) Relay teams have exactly four members; ";
    push @commands , "relay_points = reshape( rel_coeffs' , num_rr , num_swimmers )' ; ";
    push @commands , "idx = ( relay_points > 0 ) ; ";
    push @commands , "B6 = zeros( num_rr , 1 ) ; " ;
    push @commands , "A6temp = zeros( num_swimmers , num_ind + num_rr ) ; ";
    push @commands , "for j = 1 : num_rr; ";
    push @commands , "    temp = [ 1:num_swimmers ]'(idx(:,j)) ; ";
    push @commands , "    A6temp( temp(1) , j + num_ind ) = 3 ; ";
    push @commands , "    for i = 2:size(temp)(1); ";
    push @commands , "        A6temp( temp(i) , num_ind + j ) = -1 ; ";
    push @commands , "    end ";
    push @commands , "end;";
    push @commands , "for i = 1:num_rr; ";
    push @commands , "    A6_ = zeros( num_swimmers , num_ind + num_rr ) ; ";
    push @commands , "    A6_( : , num_ind + i ) = A6temp( : , num_ind + i ) ; ";
    push @commands , "    A6(i,:) = reshape( A6_' , 1 , num_swimmers * ( num_ind + num_rr ) ) ; " ;
    push @commands , "end;";
    push @commands , "A6 = [ A6 ; A6 ] ; ";
    push @commands , "B6 = [ B6 ; B6 ] ; ";
    push @commands , "Ctype6 = [ char( 'U' * ones( num_rr , 1 ) ) ; char( 'L' * ones( num_rr , 1 ) ) ] ; ";
    push @mapr , 6 ;
    }
    push @commands , "% 7th,8th Constraints - (Logical) Selection coefficients are either 1 or 0; ";
    push @commands , "B7 = ones( num_swimmers * ( num_ind + num_rr ) , 1 ) ;";
    push @commands , "Ctype7 = char( 'U' * ones( num_swimmers * ( num_ind + num_rr ) , 1 ) ) ; ";
    push @commands , "A7 = eye( num_swimmers * ( num_ind + num_rr ) , num_swimmers * ( num_ind + num_rr ) ) ; ";
    push @mapr , 7 ;
    push @commands , "B8 = zeros( num_swimmers * ( num_ind + num_rr ) , 1 ) ; ";
    push @commands , "Ctype8 = char( 'L' * ones( num_swimmers * ( num_ind + num_rr ) , 1 ) ) ; ";
    push @commands , "A8 = eye( num_swimmers * ( num_ind + num_rr ) , num_swimmers * ( num_ind + num_rr ) ) ; ";
    push @mapr , 8 ;
    
    push @commands , "% Variable is an integer; " ;
    push @commands , "Vtype = char( \"I\" * ones( num_swimmers * ( num_ind + num_rr ) , 1 ) ) ; ";
    push @commands , "sense = -1 ; ";
    push @commands , "% Bounds; ";
    push @commands , "lb = zeros( num_swimmers * ( num_ind + num_rr ) , 1 ); ";
    push @commands , "ub = Inf * ones( num_swimmers * ( num_ind + num_rr ) , 1 ); ";
    
    push @commands , "% Combine; ";
    
    my $A = join ' ; ' , map { "A$_" } @mapr ;
    push @commands , "A = [ $A ] ; ";
    
    my $B = join ' ; ' , map { "B$_" } @mapr ;
    push @commands , "B = [ $B ] ; ";
    
    my $Ctype = join ' ; ' , map { "Ctype$_" } @mapr ;
    push @commands , "Ctype = [ $Ctype ] ; ";
    
    my $cprime = '' ;
    if ( scalar @relay_coefficients == 0 )  {
        $cprime = "cprime = reshape( ind_coeffs  , num_ind , num_swimmers )' ;";
    } elsif ( scalar @ind_coefficients == 0 ) {
        $cprime = "cprime = 1/4*reshape( rel_coeffs' , num_rr , num_swimmers )' ; " ;
    } else {
        $cprime = "cprime = horzcat( reshape( ind_coeffs , num_ind , num_swimmers )' , 1/4*reshape( rel_coeffs' , num_rr , num_swimmers )' ) ;";
    }
    
    push @commands , $cprime ;
    push @commands , "c = reshape( cprime' , 1 , num_swimmers * ( num_ind + num_rr ) )  ;";
    push @commands , "[ xopt , zmx ] = glpk( c , A , B , lb , ub , Ctype , Vtype , sense );";
    #push @commands , "if \!( zmx > 0 ) xopt = ( c' > 0 ) ; zmx = sum(c') ; endif ;";
    push @commands , "xopt , zmx" ;
    
	# write HTML to file
	my $docroot = $ENV{DOCUMENT_ROOT} || '/var/www/html/' ;
	if ( substr $docroot , -1 ne '/' ) {
    	$docroot = "$docroot/" ;
	}
	my $team_info = getTeamInfo( $team_id , $dbh ) ;
	my $filetitle = $team_info->{nickname} . "_$gender" ;
	$filetitle =~ s/ /_/g ;
	$filetitle =~ s/[\(\)]//g ;
	my $filename = "${docroot}docs/pp_octave_${filetitle}.m" ;
	my $fileout  = "${docroot}docs/pp_octave_${filetitle}.out" ;
	debug ( $filename );
    chomp( $filename );
	open(my $fh, ">", $filename ) or die "cannot open > $filename for output: $!" ;
    foreach ( @commands ) {
        print $fh "$_\n" ;
    }
	close $fh ;
	my $return = `octave -q $filename > $fileout` ;

	open( $fh, "<", $fileout ) or die "Can't open file $fileout for input: $!";
	my $output = do { local $/; <$fh> };
    
    $output =~ s/(\d)\n/$1/g;
    $output =~ s/(xopt =)\s+(0|1)/$1 $2/s;
    $output =~ m/xopt =(.*?)zmx =(.*?)/s;
    my $xopt = $1;
    chomp $xopt ;
    my $idx = index $output , "zmx =" ;
    my $power_points = substr $output , $idx + 5 ;
    $power_points =~ s/^\s+|\s+$//g ; 
    #debug( $power_points ) ;
    if ( $power_points eq "NA" || $power_points eq '' || !defined $power_points ) {
        $power_points = 0 ;
    }
    
    if ( $type ne 'champs' ) {
        my ( $st , $sth ) = () ;
        $st = "INSERT INTO rankings ( team_id , gender , ranking_date , power_points ) VALUES( $team_id , '$gender' , '$date' , $power_points ) ON DUPLICATE KEY UPDATE power_points = values(power_points)" ;
        $sth = prepareExecute( $st , $dbh ) ;
        $sth->finish() ;        
    }
    
    if ( $power_points == 0 ) {
        return ( 0 ) ;
    }
    
    @commands = () ;
    push @commands , "num_swimmers = $num_swimmers;";
    push @commands , "num_ind = $num_ind;";
    push @commands , "num_rel = $num_rel;";
    push @commands , "num_r1 = $num_r1;";
    push @commands , "num_r2 = $num_r2;";
    push @commands , "num_r3 = $num_r3;";
    push @commands , "num_rr = num_r1 + num_r2 + num_r3;";
    push @commands , "ind_coeffs = [ $ind_coeffs ];" ;
    push @commands , "rel_coeffs = [ $rel_coeffs ];" ;
    push @commands , "ind_result_ids = [ $ind_result_ids ];";
    push @commands , "rel_result_ids = [ $rel_result_ids ];";
    
    my $rprime = '' ; # rprime is made of powerpoints
    my $idprime = '' ;
    if ( scalar @relay_coefficients == 0 )  {
        #debug( "No relay coefficients" ) ;
        $rprime = "rprime = reshape( ind_coeffs , num_ind , num_swimmers )' ;";
        $idprime = "idprime = reshape( ind_result_ids , num_ind , num_swimmers )' ;" ;
    } elsif ( scalar @ind_coefficients == 0 ) {
        #debug( "No individual coefficients" ) ;
        $rprime = "rprime = 1/4*reshape( rel_coeffs' , num_rr , num_swimmers )' ; " ;
        $idprime = "idprime = reshape( rel_result_ids' , num_rr , num_swimmers )' ; " ;
    } else {
        #debug( "Both Individual and Relay Coefficients present" ) ;
        $rprime = "rprime = horzcat( reshape( ind_coeffs , num_ind , num_swimmers )' , 1/4*reshape( rel_coeffs' , num_rr , num_swimmers )' ) ;";
        $idprime = "idprime = horzcat( reshape( ind_result_ids , num_ind , num_swimmers )' , reshape( rel_result_ids' , num_rr , num_swimmers )' ) ;" ;
    }

    push @commands , $rprime ;
    push @commands , $idprime ;
    push @commands , "r = reshape( rprime' , 1 , num_swimmers * ( num_ind + num_rr ) )  ;";
    push @commands , "xopt = [ $xopt ] ;";
    push @commands , "unique(idprime'(xopt > 0))'";
    
	$filename = "${docroot}docs/pp_octave_${filetitle}_2.m" ;
	$fileout  = "${docroot}docs/pp_octave_${filetitle}_2.out" ;
	debug ( $filename );
    chomp( $filename );
	open($fh, ">", $filename ) or die "cannot open > $filename for output: $!" ;
    foreach ( @commands ) {
        print $fh "$_\n" ;
    }
	close $fh ;
	$return = `octave -q $filename > $fileout` ;

	open($fh, "<", $fileout ) or die "Can't open file $fileout for input: $!";
	$output = do { local $/; <$fh> };
    
    my $results_to_use = (split '=' , $output)[1] ;
    my @results_to_use = split ' ' , $results_to_use ;
    
    use Data::Dumper ;
    my $dmsg = Dumper @results_to_use ;
    use NCPS::Events qw/ getEventInfo / ;
    debug( "Results to use: $dmsg" ) ;
    
    foreach my $result_id ( @results_to_use ) {
        my ( $st , $sth ) = () ;
        my $result_info = getInfoById( 'results' , $result_id , $dbh ) ;
        my $event_id = $result_info->{event_id} ;
        $event_id = 7 if ( $event_id == 27 ) ;
        $event_id = 8 if ( $event_id == 28 ) ;
        $event_id = 13 if ( $event_id == 29 ) ;
        $event_id = 14 if ( $event_id == 30 ) ;
        
        my ( $athlete_id , $time , $legs , $power_points ) = () ;
        $athlete_id = $result_info->{athlete_id} ;
        $time = $result_info->{time} ;
        $power_points = $result_info->{power_points} ;

        if ( $event_id == 1 || $event_id == 2 || $event_id == 17 || $event_id == 18 || $event_id == 23 || $event_id == 24 ) {
            my $st2 = "SELECT GROUP_CONCAT( convert( relays.athlete_id , char(8) ) separator '|' ) as legs FROM relays WHERE result_id = $result_id" ;
            my $sth2 = prepareExecute( $st2 , $dbh ) ;
            $legs = $sth2->fetchrow() ;
            $sth2->finish() ;
            push @{$nisca{$event_id}} , [ $legs , $time , $power_points ] ;
        } else {
            push @{$nisca{$event_id}} , [ $athlete_id , $time , $power_points ] ;
        }
    }
    
	my $nisca = \%nisca ;
	$dmsg = Dumper $event_layout ;
	#debug ( $dmsg ) ;
	$roster = \%roster ;
	$dmsg = Dumper $roster ;
	#debug ( $dmsg ) ;
	
	return ( $power_points , $nisca , $event_layout , $roster ) ;
}
    

1;
