BEGIN { 
    use lib '/var/www/html/lib';
    @INC = reverse @INC ;
    use NCPS::UTIL qw/
        prepareExecute
        getInfoById
    /;
    use NCPS qw/
        debug
    /;
    use NCPS::PowerPoints qw/ 
        getBestLineup
    /;
    use DBI ;
}

my $docroot = '/var/www/html' ;

my $db = "swimming";
my $user = "swimming";
my $pwd = "**************";
my $dsn = "DBI:mysql:${db}";

my $dbh = DBI->connect("$dsn", "$user", "$pwd");
die "connect failed: " . DBI->errstr() unless $dbh;

my $date = '2022-02-02' ;

my ( $st , $sth ) = () ;

$st = "SELECT id FROM teams_in_results WHERE association = 'NCHSAA'" ;
$sth = prepareExecute( $st , $dbh ) ;

my @teams = () ;
while ( my $team_id = $sth->fetchrow() ) {
    push @teams , $team_id ;
}

foreach my $team_id ( @teams ) {
    foreach my $gender ( 'M' , 'F' ) {

    my ( $power_points , $nisca , $event_layout , $roster ) = getBestLineup( $team_id , $gender , $date , 'champs' , $dbh ) ;
        
        $st = "delete from best_lineup_champs where team_id = $team_id and gender = '$gender' " ;
        $sth = prepareExecute( $st , $dbh ) ;
        $sth->finish() ;
        $st = "delete from best_relays_champs where entry_id not in ( select id from best_lineup_champs )" ;
        $sth = prepareExecute( $st , $dbh ) ;
        $sth->finish() ;
        
        
        foreach my $event_id ( keys %{$nisca} ) {
            my @entries = @{$nisca->{$event_id}} ;
            my $event_info = getInfoById( 'events' , $event_id , $dbh ) ;
            my $ir_flag = $event_info->{ir_flag} ;
            if ( $ir_flag eq 'I' ) {
                foreach my $entry ( @entries ) {
                    my ( $athlete_id , $time , $pp ) = @{$entry} ;
                    insertEntry( $athlete_id , $event_id , 0 , $team_id , $gender , $time , 'Y' , '' , $dbh ) ;
                }
            } else {
                my ( $legs , $time , $pp ) = @{@entries->[0]} ;
                my @legs = split '\|' , $legs ;
                my $entry_id = insertEntry( 0 , $event_id , 0 , $team_id , $gender , $time , 'Y' , 'A' , $dbh ) ;
                insertRelayEntry( $entry_id , $legs[0] , 1 , $dbh ) ;
                insertRelayEntry( $entry_id , $legs[1] , 2 , $dbh ) ;
                insertRelayEntry( $entry_id , $legs[2] , 3 , $dbh ) ;
                insertRelayEntry( $entry_id , $legs[3] , 4 , $dbh ) ;
            }
        }
    }
}        

sub insertEntry {
    my ( $athlete_id , $event_id , $meet_id , $team_id , $gender , $time , $course , $relay_designation , $dbh ) = @_ ;
    my $st = "INSERT INTO best_lineup_champs ( athlete_id, event_id, meet_id, team_id, gender, time, course, relay_designation ) VALUES ( $athlete_id , $event_id , $meet_id , $team_id , '$gender' , $time , '$course' , '$relay_designation' ) ON DUPLICATE KEY UPDATE time = $time , id=LAST_INSERT_ID(id)" ;
    my $sth = prepareExecute( $st , $dbh ) ;
    $st = "SELECT last_insert_id()" ;
    $sth = prepareExecute( $st , $dbh ) ;
    my $entry_id = $sth->fetchrow() ;
    return $entry_id ;
}

sub insertRelayEntry {
    my ( $entry_id , $athlete_id , $position , $dbh ) = @_ ;
    my ( $st , $sth ) = () ;
    
    $st = "INSERT INTO best_relays_champs ( entry_id , athlete_id , position ) VALUES ( $entry_id , $athlete_id , $position ) ON DUPLICATE KEY update athlete_id = $athlete_id" ;
    $sth = prepareExecute( $st , $dbh ) ; 
    $sth->finish() ;
}
