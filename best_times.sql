truncate best_times ;

insert into best_times
select 
    athlete_id , 
    team_id , 
    case        
            WHEN event_id = 27 THEN 7 
            WHEN event_id = 28 THEN 8 
            WHEN event_id = 29 THEN 13 
            WHEN event_id = 30 THEN 14
            ELSE event_id
    end as event_id,
    time ,
    power_points ,
    meet_id ,
    id as result_id ,
    0 as ncps_points 
FROM
    results
WHERE
    event_id < 31
    and
    dq = 'N'
    and
    time > 0 
ON DUPLICATE KEY UPDATE
    best_times.meet_id = case 
            when best_times.event_id in ( 9, 10, 25, 26 ) and best_times.time < results.time then results.meet_id
            when best_times.event_id in ( 9, 10, 25, 26 ) and best_times.time >= results.time then best_times.meet_id
            when best_times.event_id not in ( 9, 10, 25, 26 ) and best_times.time > results.time then results.meet_id
            when best_times.event_id not in ( 9, 10, 25, 26 ) and best_times.time <= results.time then best_times.meet_id
           end ,
    best_times.result_id = case 
            when best_times.event_id in ( 9, 10, 25, 26 ) and best_times.time < results.time then results.id
            when best_times.event_id in ( 9, 10, 25, 26 ) and best_times.time >= results.time then best_times.result_id
            when best_times.event_id not in ( 9, 10, 25, 26 ) and best_times.time > results.time then results.id
            when best_times.event_id not in ( 9, 10, 25, 26 ) and best_times.time <= results.time then best_times.result_id
           end ,
    best_times.power_points = case 
            when best_times.event_id in ( 9, 10, 25, 26 ) and best_times.time < results.time then results.power_points
            when best_times.event_id in ( 9, 10, 25, 26 ) and best_times.time >= results.time then best_times.power_points
            when best_times.event_id not in ( 9, 10, 25, 26 ) and best_times.time > results.time then results.power_points
            when best_times.event_id not in ( 9, 10, 25, 26 ) and best_times.time <= results.time then best_times.power_points
           end ,
    best_times.time = case 
            when best_times.event_id in ( 9, 10, 25, 26 ) and best_times.time < results.time then results.time
            when best_times.event_id in ( 9, 10, 25, 26 ) and best_times.time >= results.time then best_times.time
            when best_times.event_id not in ( 9, 10, 25, 26 ) and best_times.time > results.time then results.time
            when best_times.event_id not in ( 9, 10, 25, 26 ) and best_times.time <= results.time then best_times.time
           end 
;

update 
    best_times join ncps_points 
    on 
    best_times.event_id = ncps_points.event_id 
set 
    best_times.ncps_points = 
        case 
            when best_times.event_id in ( 9, 10, 25, 26 ) then floor(( ncps_points.max / ncps_points.target ) * ( best_times.time ))
            else floor( -1 * ( ncps_points.max / ncps_points.target ) * ( best_times.time - ncps_points.target ) + ncps_points.max )
        end
;
