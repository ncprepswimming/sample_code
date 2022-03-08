package NCPS::Teams;

use strict;
use warnings;
use lib '/var/www/html/lib' ;
use NCPS::UTIL qw/ prepareExecute getInfoById / ;
use NCPS::Entries qw/ getSwimmerRankings / ;
use NCPS::SQL qw/ getTableColumns / ;
use NCPS qw / debug / ; 

my $debug = 1 ;
our (@ISA, @EXPORT_OK);

BEGIN {

    require Exporter;
    
    @ISA = qw(Exporter);
    
    @EXPORT_OK = qw/
    createAthlete
    addAthleteToTeam
    mergeAthletes
    getTeamInfo
    getSchedule
    getRoster
    getAthlete
    updateAthlete
    assignTeam
    getMyMeets
    addAthleteIfNotExists
    mergeTeams
    storeAthleteIDTemp
    removeAthleteFromRoster
    storeCreatedAthletes
    getPostSeasonStandards
    getBestTimes
    getBestTimes2
    getBestTimesUnverified
    getAllTeams
    getAllAthletes
    /;
}

sub getAllTeams {
    my $dbh = shift ;
    my %teams = () ;
    my $st = "SELECT id FROM teams" ;
    my $sth = prepareExecute( $st , $dbh ) ;
    while ( my $team_id = $sth->fetchrow() ) {
        my $team_info = getInfoById( 'teams' , $team_id , $dbh ) ;
        $teams{$team_id} = $team_info ;
    }
    return \%teams ;
}

sub getAllAthletes {
    my $dbh = shift ;
    my %athletes = () ;
    my $st = "SELECT id FROM athletes" ;
    my $sth = prepareExecute( $st , $dbh ) ;
    while ( my $athlete_id = $sth->fetchrow() ) {
        my $athlete_info = getInfoById( 'athletes' , $athlete_id , $dbh ) ;
        $athletes{$athlete_id} = $athlete_info ;
    }
    return \%athletes ;
}


sub mergeTeams {
    my ( $old_team , $new_team , $dbh ) = @_ ;
    my ( $st , $sth ) = () ;
    # assign all entries from $old_team to $new_team ;
    $st = "
UPDATE 
    entries
SET
    team_id = $new_team
WHERE
    team_id = $old_team
";
    $sth = prepareExecute( $st , $dbh ) ;
    $sth -> finish() ;
    
    # assign all results from $old_team to $new_team ;
    $st = "
UPDATE 
    results
SET
    team_id = $new_team
WHERE
    team_id = $old_team
";
    $sth = prepareExecute( $st , $dbh ) ;
    $sth -> finish() ;
    
    # re-assign all meet_rosters rows
    $st = "
UPDATE 
    meet_rosters
SET
    team_id = $new_team
WHERE
    team_id = $old_team
";
    $sth = prepareExecute( $st , $dbh ) ;
    $sth -> finish() ;
    
    # re-assign all scores rows
    $st = "
UPDATE 
    scores
SET
    team_id = $new_team
WHERE
    team_id = $old_team
";
    $sth = prepareExecute( $st , $dbh ) ;
    $sth -> finish() ;
    
    # re-assign all event_scores rows 
    $st = "
UPDATE 
    event_scores
SET
    team_id = $new_team
WHERE
    team_id = $old_team
";
    $sth = prepareExecute( $st , $dbh ) ;
    $sth -> finish() ;
    
    # assign all athletes from $old_team to $new_team ;
    $st = "
UPDATE 
    team_rosters
SET
    team_id = $new_team
WHERE
    team_id = $old_team
";
    $sth = prepareExecute( $st , $dbh ) ;
    $sth -> finish() ;
}

sub assignTeam {
    my ( $user_id , $team_id , $dbh ) = @_ ;
    my $st = "
INSERT INTO
    coaches ( team, coach )
VALUES
    ( $team_id , $user_id )
ON DUPLICATE KEY UPDATE coach = $user_id 
" ;
    my $sth = prepareExecute( $st , $dbh ) ;
    $sth->finish() ;
    
    $st = "SELECT current_year_paid FROM teams WHERE id = $team_id" ;
    $sth = prepareExecute( $st , $dbh ) ;
    my $current_year_paid = $sth->fetchrow() ;
    $sth->finish() ;
    
    $st = "UPDATE coaches SET current_year_paid = $current_year_paid" ;
    $sth = prepareExecute( $st , $dbh ) ;
    $sth->finish() ;
}

sub updateAthlete {
    my ( $ncps_id , $year, $dob , $dbh ) = @_;
    my ($sec,$min,$hour,$mday,$mon,$tyear,$wday,$yday,$isdst) = localtime();
    my $senioryear = $tyear + 1900 ;
    if ( $mon > 6 ) {
        $senioryear += 1 ;
    }
    
    my ( $st , $sth ) = () ;
    $st = "SELECT year , dob FROM athletes WHERE id = $ncps_id" ;
    $sth = prepareExecute ( $st , $dbh ) ;
    my ( $current_year , $current_dob ) = $sth->fetchrow() ;
    $sth->finish() ;

    $dob = $current_dob if ( $dob eq '0000-00-00' ) ;
    $year = $current_year if ( $year eq '' ) ;
        
    $year = "SR" if ( $year eq '12' ) ;
    $year = "JR" if ( $year eq '11' ) ;
    $year = "SO" if ( $year eq '10' ) ;
    $year = "FR" if ( $year eq '09' ) ;
    
    my %year_map = (
        "SR" => $senioryear ,
        "JR" => $senioryear + 1 ,
        "SO" => $senioryear + 2 ,
        "FR" => $senioryear + 3 ,
        "08" => $senioryear + 4 ,
        "07" => $senioryear + 5 ,
        "06" => $senioryear + 6 ,
        "05" => $senioryear + 7 ,
    );
    
    my $gradyr = $year_map{$year} || '' ;
    
    $st = "
    UPDATE
        athletes
    SET
        year = '$year',
        graduation_year = '$gradyr' ,
        dob = '$dob' ,
        active = 1 
    WHERE
        id = $ncps_id
    ";
    debug( $st ) ;
    $sth = prepareExecute( $st , $dbh ) ;
    $sth->finish() ;
}

sub createAthlete {
    my ( $first , $last , $gender , $year , $gradyr ,  $dob , $dbh ) = @_ ;
    my ($sec,$min,$hour,$mday,$mon,$tyear,$wday,$yday,$isdst) = localtime();
    my $senioryear = $tyear + 1900 ;
    if ( $mon > 6 ) {
        $senioryear += 1 ;
    }
    
    $year = "SR" if ( $year eq '12' ) ;
    $year = "JR" if ( $year eq '11' ) ;
    $year = "SO" if ( $year eq '10' ) ;
    $year = "FR" if ( $year eq '09' ) ;
    
    my %year_map = (
        "SR" => $senioryear ,
        "JR" => $senioryear + 1 ,
        "SO" => $senioryear + 2 ,
        "FR" => $senioryear + 3 ,
        "08" => $senioryear + 4 ,
        "07" => $senioryear + 5 ,
        "06" => $senioryear + 6 ,
        "05" => $senioryear + 7 ,
    );
    
    if ( $gradyr eq '' ) {
        $gradyr = $year_map{$year} || '' ;
    }
    if ( $year eq '' ) {
        my %new_year_map = reverse %year_map ;
        $year = $new_year_map{$gradyr} || '' ;
    }
    
    my $st = "
    INSERT INTO
        athletes
    ( first , last , gender , year , graduation_year , dob )
    VALUES
    ( '$first' , '$last' , '$gender' , '$year' , '$gradyr' , '$dob' )
    ";
    my $sth = prepareExecute( $st , $dbh ) ;
    $sth->finish();
    $st = "SELECT LAST_INSERT_ID()";
    $sth = prepareExecute( $st , $dbh ) ;
    my $athlete_id = $sth->fetchrow();
    $sth->finish();
    $athlete_id =~ s/\D//gs;
    return $athlete_id ;
}   

sub addAthleteToTeam {
    my ( $athlete_id , $team_id , $dbh ) = @_ ;
    my $st = "
    INSERT INTO
        team_rosters
    ( team_id , athlete_id )
    VALUES
    ( $team_id , $athlete_id )
    ";
    my $sth = prepareExecute( $st , $dbh );
    $sth->finish();
}

sub addAthleteIfNotExists {
    my ( $team_id , $gender , $first , $last , $year , $dob , $dbh ) = @_ ;
    $first =~ s/\'/\\'/g ;
    $last =~ s/\'/\\'/g ;
    my ( $st , $sth ) = () ;
    $st = "
    SELECT 
        athletes.id 
    FROM 
        athletes
        JOIN
        team_rosters
        ON athletes.id = team_rosters.athlete_id
    WHERE
        team_id = $team_id 
        and
        gender = '$gender'
        and
        first = '$first'
        and
        last = '$last'
    ";
    debug( $st ) ;
    $sth = prepareExecute( $st , $dbh ) ;
    my $athlete_id = $sth->fetchrow() || 0 ;
    if ( $athlete_id ) { return $athlete_id; }
    else {
        $athlete_id = createAthlete( $first , $last , $gender , $year , '' , '' , $dbh ) ;
        storeAthleteIDTemp( $athlete_id , $dbh ) ;
        addAthleteToTeam( $athlete_id , $team_id , $dbh ) ;
        return $athlete_id ;
    }
}

sub mergeAthletes {

    my ( $keep , $merge , $dbh ) = @_ ;
    my ( $st , $sth ) = () ;
    
    # make sure that keep and merge don't represent distinct result records.
    
    $st = "select meet_id , team_id , event_id , athlete_id from results where athlete_id in ( $keep , $merge )" ;
    $sth = prepareExecute( $st , $dbh ) ;
    
    my %results = () ;
    while ( my @data = $sth->fetchrow() ) {
        my ( $meet_id , $team_id , $event_id , $athlete_id ) = @data ;
        if ( defined $results{$meet_id}{$team_id}{$event_id} ) {
            my $st2 = "DELETE from results where meet_id = $meet_id and team_id = $team_id and event_id = $event_id and athlete_id = $athlete_id" ;
            my $sth2 = prepareExecute( $st2 , $dbh ) ;
        } else {
            $results{$meet_id}{$team_id}{$event_id} = $athlete_id ;
        }
    }
    
    $st = "update results set athlete_id = $keep where athlete_id = $merge" ;
    $sth = prepareExecute( $st , $dbh ) ;
    $sth->finish() ;
    
    $st = "update relays set athlete_id = $keep where athlete_id = $merge" ;
    $sth = prepareExecute( $st , $dbh ) ;
    $sth->finish() ;
    
    $st = "update entries set athlete_id = $keep where athlete_id = $merge" ;
    $sth = prepareExecute( $st , $dbh ) ;
    $sth->finish() ;
   
    $st = "update relay_entries set athlete_id = $keep where athlete_id = $merge" ;
    $sth = prepareExecute( $st , $dbh ) ;
    $sth->finish() ;
 
    $st = "delete from team_rosters where athlete_id = $merge" ;
    $sth = prepareExecute( $st , $dbh ) ;
    $sth->finish() ;
    
    $st = "update athletes set active = 1 where id = $keep" ;
    $sth = prepareExecute( $st , $dbh ) ;
    $sth->finish() ;

    $st = "update athletes set active = 0 where id = $merge" ;
    $sth = prepareExecute( $st , $dbh ) ;
    $sth->finish() ;

}

sub getTeamInfo {
    my ($team_id,$dbh) = @_;
    my $st = "SELECT name, nickname, mascot, classification, abbreviation, hytek_short_name, association FROM teams WHERE id = $team_id";
    my $sth = prepareExecute($st,$dbh);
    my ($team_name, $nickname, $mascot, $classification, $abbreviation, $hytek_short_name, $association ) =  $sth->fetchrow();
    $sth->finish();
    my %team_info = (
        name           => $team_name,
        mascot         => $mascot,
        nickname       => $nickname,
        classification => $classification,
        abbreviation   => $abbreviation,
        hytek_short_name => $hytek_short_name,
        association    => $association ,
    );
    $st = "SELECT coach FROM coaches WHERE team = $team_id" ;
    $sth = prepareExecute( $st , $dbh ) ;
    my $coach = $sth->fetchrow();
    $sth->finish() ;
    $team_info{coach} = $coach ;
    my $team_info = \%team_info; 
    return $team_info;
}

sub getMyMeets {
    my ( $team_id , $dbh ) = @_ ;
    my %meets = () ;
    my $st = "
SELECT 
	DISTINCT meets.id,
	meets.name, 
	meets.nickname,
	date, 
	location, 
	GROUP_CONCAT( DISTINCT CONVERT( team_id , CHAR(8)) SEPARATOR '|' ) AS team_id_list,
	GROUP_CONCAT( DISTINCT teams.nickname SEPARATOR '|' ) AS team_nickname_list 
FROM 
	meets 
	JOIN 
	meet_rosters 
	ON 
	meets.id = meet_rosters.meet_id 
	JOIN
	teams
	ON 
	meet_rosters.team_id = teams.id
WHERE
	meets.id in (SELECT meet_id FROM meet_rosters WHERE team_id = $team_id )
	and
	meets.date <= CURDATE() 
	and 
	meets.sub_meet = 0 
GROUP BY 
	id
    ";
    my $sth = prepareExecute( $st , $dbh ) ;
    while ( my @data = $sth->fetchrow() ) {
        my ( $id , $name , $nickname , $date , $location , $team_ids , $team_nicknames ) = @data ;
        $meets{$id}{nickname} = $nickname ;
        $meets{$id}{name} = $name ;
        $meets{$id}{date} = $date ;
        $meets{$id}{location} = $location ;
        $meets{$id}{team_ids} = $team_ids ;
        $meets{$id}{team_nicknames} = $team_nicknames ;
    }
    my $meets = \%meets ;
    return $meets ;

}

sub getSchedule {
    my ($team_id,$dbh) = @_;
    my $st = "SELECT
                m.id,
                coalesce(m.name,m.nickname) as name,
                m.date,
                m.location,
                GROUP_CONCAT( DISTINCT t.nickname SEPARATOR '|' ) AS team_nickname_list 
            FROM
                meets m
            JOIN
                meet_rosters mr
            ON
                m.id = mr.meet_id
            JOIN
                teams t
            ON
                mr.team_id = t.id
            WHERE
                mr.team_id = $team_id";
    my $sth = prepareExecute($st,$dbh);
    my ($meet_id,$meet_name,$meet_date,$meet_location,$team_nickname_list) = ();
    my %schedule = ();
    while ( ($meet_id,$meet_name,$meet_date,$meet_location,$team_nickname_list) = $sth->fetchrow() ) {
        $schedule{$meet_id}{date} = $meet_date;
        $schedule{$meet_id}{name} = $meet_name;
        $schedule{$meet_id}{location} = $meet_location;
        $schedule{$meet_id}{team_nickname_list} = $team_nickname_list ;
    }
    $sth->finish();
    my $schedule = \%schedule;
    return $schedule;
}

sub getRoster {
    use String::Util qw/trim/ ;
    my ( $team_id , $gender , $dbh ) = @_;
    my %roster = ();
    my $gender_where_st = '';
    if ( $gender eq 'M' or $gender eq 'F' ) {
        $gender_where_st = "AND a.gender = '$gender'";
    }
    my $st = "
    SELECT
        a.id, 
        first, 
        middle, 
        last,
        nick, 
        year,
        graduation_year,
        gender,
        dob,
        active
    FROM
        team_rosters t
        JOIN
        athletes a
        ON
        t.athlete_id = a.id
    WHERE
        active = 1 and
        t.team_id = $team_id
        $gender_where_st
    ";

    my $sth = prepareExecute( $st , $dbh ) ;
    while ( my @data = $sth->fetchrow() ) {
        my ( $id , $first , $middle , $last , $nick , $year , $gradyr , $gen , $dob , $active ) = @data;
        
        $middle = ($middle)?$middle:'' ;
        
        $roster{$id}{first} = $first ;
        $roster{$id}{middle} = $middle ;
        $roster{$id}{last} = $last ;
        $roster{$id}{dob} = $dob ;
        $roster{$id}{name} = "$first $middle $last";
        $roster{$id}{nick} = $nick ;
        $roster{$id}{flname} = "$first $last";
        if ( trim($nick) ne '' ) { $roster{$id}{nkname} = "$nick $last" ; }
        $roster{$id}{year} = $year ;
        $roster{$id}{gradyr} = $gradyr ;
        $roster{$id}{gender} = $gen ;
        $roster{$id}{active} = $active ;
    }
    $sth->finish();
    my $roster = \%roster;
    return $roster;
}

sub getAthlete {
    my ( $athlete_id , $dbh ) = @_ ;
    my $st = "
    SELECT 
        * 
    FROM
        athletes
    WHERE
        id = $athlete_id" ;
    my $sth = prepareExecute( $st , $dbh ) ;
    my @data = $sth->fetchrow() ;
    map { $_ = (defined $_)?$_:'' } @data ;
    my ( $id , $last , $middle , $first , $nick , $dob , $year , $graduation_year , $gender ) = @data ;
    $sth->finish() ;
    my %athlete = () ;
    $athlete{first} = $first || '' ;
    $athlete{last} = $last || '' ;
    $athlete{dob} = $dob ;
    $athlete{middle} = $middle || '' ; 
    $athlete{name} = "$athlete{first} $athlete{middle} $athlete{last}";
    $athlete{nick} = $nick || '';
    $athlete{flname} = "$athlete{first} $athlete{last}";
    if ( trim($athlete{nick}) ne '' ) { $athlete{nkname} = "$athlete{nick} $last" ; }
    $athlete{year} = $year ;
    $athlete{gradyr} = $graduation_year ;
    $athlete{gender} = $gender ;
    return \%athlete ;
}

sub storeAthleteIDTemp {
    my ( $athlete_id , $dbh ) = @_ ;
    my $st = "
INSERT INTO
    meet_athletes_temp
    ( athlete_id )
VALUES 
    ( $athlete_id ) 
";
    my $sth = prepareExecute( $st , $dbh ) ;
    $sth->finish() ;
}

sub storeCreatedAthletes {
    my ( $meet_id , $dbh ) = @_ ;
    my $st = "
INSERT INTO
    athletes_added_by_meet
    ( athlete_id ) 
SELECT 
    athlete_id
FROM
    meet_athletes_temp
";
    my $sth = prepareExecute( $st , $dbh ) ;
    $st = "
UPDATE 
    athletes_added_by_meet
SET
    meet_id = $meet_id
";    
    $sth = prepareExecute( $st , $dbh ) ;
    
    $st = "
DELETE FROM
    meet_athletes_temp
";
    $sth = prepareExecute( $st , $dbh ) ;
    $sth->finish() ;
}

sub removeAthleteFromRoster {
    my ( $team_id , $athlete_id , $dbh ) = @_ ;
    my ( $st , $sth ) = () ;
    $st = "DELETE FROM team_rosters WHERE team_id = $team_id AND athlete_id = $athlete_id" ;
    $sth = prepareExecute( $st , $dbh ) ;
    $sth->finish() ;
}

sub getPostSeasonStandards {
    my ( $team_id , $dbh ) = @_ ;
    my $team_info = getInfoById( 'teams' , $team_id , $dbh ) ;
    my $association = $team_info->{association} ;
    my $classification = $team_info->{classification} ;
    
    my ( $st , $sth ) = () ;
    $st = "SELECT max(id) FROM standard_sets WHERE description LIKE '$association $classification\%'" ;
    $sth = prepareExecute( $st , $dbh ) ;
    my $standard_set = $sth->fetchrow() ;
    $sth->finish() ;
    return $standard_set ;
}

sub getBestTimes {
    my ( $team_id , $dbh ) = @_ ;
    my $team_info = getInfoById( 'teams' , $team_id , $dbh ) ;
    my $association = lc ( $team_info->{association} ) ;
    my ( $st , $sth ) = () ;
    my %bestTimes_F = () ;
    my %bestTimes_M = () ;
    my %bestRelays_F = () ;
    my %bestRelays_M = () ;
    
    $st = "SELECT
    distinct
    team_results.athlete_id ,
    team_results.meet_id ,
    team_results.event_id , 
    case when( events.sd_flag = 'S' ) then min(team_results.time) else max(team_results.time) end as time ,
    team_results.power_points ,
    meets.date ,
    events.reference_event 
FROM
    (
        SELECT 
            *
        FROM
            results
        WHERE
            team_id = $team_id
            and
            time > 0
            and
            dq = 'N'
    ) as team_results    
    join
    meets on team_results.meet_id = meets.id
    join
    events on team_results.event_id = events.id
WHERE
    meets.${association}_sanctioned = 1 
        and
    meets.results_certified = 'Y' 
        and
    events.ir_flag = 'I'
GROUP BY
    athlete_id,
    event_id
" ;
    $sth = prepareExecute( $st , $dbh ) ;
    while ( my @data = $sth->fetchrow() ) {
    my ( $athlete_id , $meet_id , $event_id , $best_time , $power_points , $date , $reference_event ) = @data ;
        if ( $event_id % 2 ) {
            $bestTimes_F{$athlete_id}{$event_id}{time} = $best_time ;
            $bestTimes_F{$athlete_id}{$event_id}{meet_id} = $meet_id ;
            $bestTimes_F{$athlete_id}{$event_id}{power_points} = $power_points ;
            $bestTimes_F{$athlete_id}{$event_id}{date} = $date ;
            $bestTimes_F{$athlete_id}{$event_id}{reference_event} = $reference_event ;
        } else { 
            $bestTimes_M{$athlete_id}{$event_id}{time} = $best_time ;
            $bestTimes_M{$athlete_id}{$event_id}{meet_id} = $meet_id ;
            $bestTimes_M{$athlete_id}{$event_id}{power_points} = $power_points ;
            $bestTimes_M{$athlete_id}{$event_id}{date} = $date ;
            $bestTimes_M{$athlete_id}{$event_id}{reference_event} = $reference_event ;
        }
    }
    $sth->finish() ;
    
    $st = "SELECT
    distinct
    team_results.meet_id ,
    team_results.event_id , 
    case when( events.sd_flag = 'S' ) then min(team_results.time) else max(team_results.time) end as time ,
    team_results.power_points ,
    meets.date 
FROM
    (
        SELECT 
            *
        FROM
            results
        WHERE
            team_id = $team_id
            and
            time > 0
            and
            dq = 'N'
    ) as team_results    
    join
    meets on team_results.meet_id = meets.id
    join
    events on team_results.event_id = events.id
WHERE
    meets.${association}_sanctioned = 1 
        and
    meets.results_certified = 'Y' 
        and
    events.ir_flag = 'R'
GROUP BY
    athlete_id,
    event_id
    ";
    $sth = prepareExecute( $st , $dbh ) ;
    while ( my @data = $sth->fetchrow() ) {
    my (  $meet_id , $event_id , $best_time , $power_points , $date ) = @data ;
        if ( $event_id % 2 ) {
            $bestRelays_F{$event_id}{time} = $best_time ;
            $bestRelays_F{$event_id}{meet_id} = $meet_id ;
            $bestRelays_F{$event_id}{power_points} = $power_points ;
            $bestRelays_F{$event_id}{date} = $date ;
        } else { 
            $bestRelays_M{$event_id}{time} = $best_time ;
            $bestRelays_M{$event_id}{meet_id} = $meet_id ;
            $bestRelays_M{$event_id}{power_points} = $power_points ;
            $bestRelays_M{$event_id}{date} = $date ;
        }
    }
    $sth->finish() ;
    
    
    return [ \%bestRelays_F , \%bestRelays_M , \%bestTimes_F , \%bestTimes_M ] ;
}

sub getBestTimesUnverified {
    my ( $team_id , $dbh ) = @_ ;
    my $team_info = getInfoById( 'teams' , $team_id , $dbh ) ;
    my $association = lc ( $team_info->{association} ) ;
    my ( $st , $sth ) = () ;
    my %bestTimes_F = () ;
    my %bestTimes_M = () ;
    my %bestRelays_F = () ;
    my %bestRelays_M = () ;
    
    $st = "SELECT
    distinct
    team_results.athlete_id ,
    team_results.meet_id ,
    team_results.event_id , 
    case when( events.sd_flag = 'S' ) then min(team_results.time) else max(team_results.time) end as time ,
    team_results.power_points ,
    meets.date ,
    events.reference_event 
FROM
    (
        SELECT 
            *
        FROM
            results
        WHERE
            team_id = $team_id
            and
            time > 0
            and
            dq = 'N'
    ) as team_results    
    join
    meets on team_results.meet_id = meets.id
    join
    events on team_results.event_id = events.id
WHERE
    meets.${association}_sanctioned = 1 
        and
    events.ir_flag = 'I'
GROUP BY
    athlete_id,
    event_id
" ;
    $sth = prepareExecute( $st , $dbh ) ;
    while ( my @data = $sth->fetchrow() ) {
    my ( $athlete_id , $meet_id , $event_id , $best_time , $power_points , $date , $reference_event ) = @data ;
        if ( $event_id % 2 ) {
            $bestTimes_F{$athlete_id}{$event_id}{time} = $best_time ;
            $bestTimes_F{$athlete_id}{$event_id}{meet_id} = $meet_id ;
            $bestTimes_F{$athlete_id}{$event_id}{power_points} = $power_points ;
            $bestTimes_F{$athlete_id}{$event_id}{date} = $date ;
            $bestTimes_F{$athlete_id}{$event_id}{reference_event} = $reference_event ;
        } else { 
            $bestTimes_M{$athlete_id}{$event_id}{time} = $best_time ;
            $bestTimes_M{$athlete_id}{$event_id}{meet_id} = $meet_id ;
            $bestTimes_M{$athlete_id}{$event_id}{power_points} = $power_points ;
            $bestTimes_M{$athlete_id}{$event_id}{date} = $date ;
            $bestTimes_M{$athlete_id}{$event_id}{reference_event} = $reference_event ;
        }
    }
    $sth->finish() ;
    $st = "SELECT
    distinct
    team_results.meet_id ,
    team_results.event_id , 
    case when( events.sd_flag = 'S' ) then min(team_results.time) else max(team_results.time) end as time ,
    team_results.power_points ,
    meets.date
FROM
    (
        SELECT 
            *
        FROM
            results
        WHERE
            team_id = $team_id
            and
            time > 0
            and
            dq = 'N'
    ) as team_results    
    join
    meets on team_results.meet_id = meets.id
    join
    events on team_results.event_id = events.id
WHERE
    meets.${association}_sanctioned = 1 
        and
    events.ir_flag = 'R'
        and
    events.reference_event <> 0

GROUP BY
    athlete_id,
    event_id
    ";
    $sth = prepareExecute( $st , $dbh ) ;
    while ( my @data = $sth->fetchrow() ) {
    my (  $meet_id , $event_id , $best_time , $power_points , $date ) = @data ;
        if ( $event_id % 2 ) {
            $bestRelays_F{$event_id}{time} = $best_time ;
            $bestRelays_F{$event_id}{meet_id} = $meet_id ;
            $bestRelays_F{$event_id}{power_points} = $power_points ;
            $bestRelays_F{$event_id}{date} = $date ;
        } else { 
            $bestRelays_M{$event_id}{time} = $best_time ;
            $bestRelays_M{$event_id}{meet_id} = $meet_id ;
            $bestRelays_M{$event_id}{power_points} = $power_points ;
            $bestRelays_M{$event_id}{date} = $date ;
        }
    }
    $sth->finish() ;
    
    
    return [ \%bestRelays_F , \%bestRelays_M , \%bestTimes_F , \%bestTimes_M ] ;
}

sub getBestTimes2 {
    my $year = 1900 + (localtime)[5];
    my $freshman_year = $year + 3 ;
    my ( $team_id , $gender , $type , $dbh ) = @_ ;
    my $team_info = getInfoById( 'teams' , $team_id , $dbh ) ;
    my ( $st , $sth ) = () ;
    my %best_times = () ;
    $st = "SELECT athlete_id , event_id , time , meet_id , power_points , ncps_points , result_id FROM best_times WHERE team_id = $team_id" ;
    $sth = prepareExecute( $st , $dbh ) ;
    while ( my @data = $sth->fetchrow() ) {
        my ( $athlete_id , $event_id , $time , $meet_id , $power_points , $ncps_points , $result_id ) = @data ;
        my $athlete_info = getInfoById( 'athletes' , $athlete_id , $dbh ) ;
        my $graduation_year = $athlete_info->{graduation_year} || 0 ;
        my $athlete_gender = $athlete_info->{gender} ;
        next if ( $graduation_year > $freshman_year || $athlete_gender ne $gender ) ;
        if ( $athlete_id ) {
            $best_times{$athlete_id}{meta}{name} = "$athlete_info->{first} $athlete_info->{last}";
            $best_times{$athlete_id}{meta}{display_name} = "$athlete_info->{first} $athlete_info->{last} ($athlete_info->{year})";
            $best_times{$athlete_id}{meta}{sort_name} = "$athlete_info->{last} $athlete_info->{first}";
        } else {
            $best_times{$athlete_id}{meta}{name} = $team_info->{nickname} ;
            $best_times{$athlete_id}{meta}{display_name} = "$team_info->{nickname} $team_info->{mascot}";
            $best_times{$athlete_id}{meta}{sort_name} = $team_info->{nickname} ;
        }
        $best_times{$athlete_id}{times}{$event_id}{time} = $time;
        $best_times{$athlete_id}{times}{$event_id}{pp} = $power_points;
        $best_times{$athlete_id}{times}{$event_id}{ncps_points} = $ncps_points;
        $best_times{$athlete_id}{times}{$event_id}{result_id} = $result_id ;
        $best_times{$athlete_id}{times}{$event_id}{meet_id} = $meet_id ;
    }
    
    if ( $type eq 'points' || $type eq 'nisca' || $type eq 'champs' ) {
        delete $best_times{0} ;
        
        if ( scalar keys %best_times > 30 ) {
            my $roster_size = scalar keys %best_times ;
            my $swimmers_to_cut = $roster_size - 30 ;
            my $rankings = getSwimmerRankings( $team_id , $gender , $dbh ) ;
            my %rankings = %{$rankings} ;
            use Data::Dumper ;
#              foreach my $athlete_id ( sort { $rankings{$a}{score} <=> $rankings{$b}{score} } keys %rankings ) {
#                  next if ( $rankings{$athlete_id}{is_diver} ) ;
#                  if ( $swimmers_to_cut > 0 ) {
#                      print ( "$athlete_id\n" ) ;
#                      delete $best_times{$athlete_id} ;
#                      $swimmers_to_cut -= 1 ;
#                  }
#              }
        }
    }

    #print Dumper %best_times ;
    return \%best_times ;
}

1;

