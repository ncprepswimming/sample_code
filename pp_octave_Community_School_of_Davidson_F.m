% declare quantities;
num_swimmers = 12;
num_ind = 9;
num_rel = 3;
num_r1 = 6;
num_r2 = 7;
num_r3 = 3;
num_rr = num_r1 + num_r2 + num_r3;
pstel = 4;
psiel = 2;
ptiel = 4;
ptrel = 1;
ind_coeffs = [ 599 0 494 0 0 0 590 0 0 0 0 643 0 0 632 0 437 0 693 0 773 0 576 781 0 544 0 660 670 -786 0 0 664 618 641 0 0 0 470 0 0 0 0 214 0 0 0 0 495 0 0 0 0 0 0 639 616 0 0 0 0 0 625 0 0 604 0 0 673 0 0 642 378 0 546 0 0 477 0 0 0 0 816 775 0 0 0 0 762 815 0 0 557 0 0 0 0 0 476 852 0 894 0 823 889 0 0 0 ];
rel_coeffs = [ 0 0 0 0 0 1753 0 0 0 0 0 2155 2146 0 0 2040 0 1811 1784 0 1668 1753 0 2420 0 2059 0 0 0 0 0 0 2235 1811 0 2140 0 0 2619 2420 2330 2059 0 2155 2146 2520 1986 2040 2235 1811 1784 2140 0 1753 2619 0 0 2059 0 0 0 2520 1986 2040 0 0 0 0 0 0 0 0 0 2059 1883 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 1784 2140 0 1753 0 0 2330 0 0 2155 2146 0 0 0 0 1811 1784 2140 1668 0 0 0 0 0 1883 0 0 0 0 0 0 0 0 0 1668 0 0 0 0 0 1883 0 0 0 1986 0 2235 0 0 0 0 0 2619 2420 2330 0 0 0 2146 2520 0 2040 0 0 0 0 1668 0 0 0 0 0 1883 0 0 0 1986 0 2235 0 0 0 0 0 2619 2420 2330 0 0 2155 0 2520 0 0 ];
% 1st Constraint - Per-Swimmer-Total-Event-Limit ;
B1 = pstel * ones( 12 , 1 ) ; 
Ctype1 = char( 'U' * ones( 12 , 1 ) ); 
for i=1:num_swimmers;
    A1_temp = zeros( num_swimmers , num_ind + num_rr ) ; 
    A1_temp(i,:) = ones( 1 , num_ind + num_rr ) ; 
    A1(i,:) = reshape( A1_temp' , 1 , num_swimmers * ( num_ind + num_rr ) ) ; 
end;
% 2nd Constraint - Per-Team-Individual-Event-Limit; 
B2 = ptiel * ones( num_ind , 1 ) ; 
Ctype2 = char( 'U' * ones( num_ind , 1 ) ) ;
for i=1:num_ind; 
    A2_temp = zeros( num_swimmers , num_ind + num_rr ) ; 
    A2_temp(:,i) = ones( num_swimmers , 1 ) ; 
    A2(i,:) = reshape( A2_temp' , 1 , num_swimmers * ( num_ind + num_rr ) ) ; 
end;
% 3rd Constraint - Per-Swimmer-Individual-Event-Limit; 
B3 = psiel * ones( num_swimmers , 1 ) ;
Ctype3 = char( 'U' * ones( num_swimmers , 1 ) ) ;  
for i=1:num_swimmers;
    A3_temp = zeros( num_swimmers , num_ind + num_rr ) ;
    A3_temp(i,:) = horzcat( ones( 1 , num_ind ) , zeros( 1 , num_rr ) ) ; 
    A3(i,:) = reshape( A3_temp' , 1 , num_swimmers * ( num_ind + num_rr ) ) ; 
end;
% 4th Constraint - Per-Team-Relay-Event-Limit (e.g, 2 for dual, 1 for championship); 
B4 = 4 * ptrel * ones( num_rel , 1 ) ; 
B4Z = 4 * ptrel * zeros( num_rel , 1 ) ; 
A41 = horzcat( zeros( num_swimmers , num_ind ) , ones( num_swimmers , num_r1 ) , zeros( num_swimmers , num_r2 + num_r3 ) ) ; 
A4(1,:) = reshape( A41' , 1 , num_swimmers * ( num_ind + num_rr ) ) ; 
A42 = horzcat( zeros( num_swimmers , num_ind + num_r1 ) , ones( num_swimmers , num_r2 ) , zeros( num_swimmers , num_r3 ) ) ; 
A4(2,:) = reshape( A42' , 1 , num_swimmers * ( num_ind + num_rr ) ) ; 
A43 = horzcat( zeros( num_swimmers , num_ind + num_r1 + num_r2 ) , ones( num_swimmers , num_r3 ) ) ; 
A4(3,:) = reshape( A43' , 1 , num_swimmers * ( num_ind + num_rr ) ) ; 
B4 = [ B4 ; B4Z ];
A4 = [ A4 ; A4 ];
Ctype4 = [ char( 'U' * ones( num_rel , 1 ) ) ; char( 'L' * ones( num_rel , 1 ) ) ] ; 
% 5th Constraint - (Logical) Swimmer can't be on A and B of same Relay Event.; 
B5 = ones( num_rel * num_swimmers , 1 ) ; 
Ctype5 = char( 'U' * ones( num_rel * num_swimmers  , 1 ) ) ; 
for i = 1 : num_swimmers ; 
    tmp = zeros( num_swimmers , num_ind + num_rr ) ; 
    tmp( i , num_ind+1:num_ind+num_r1 ) = ones( 1 , num_r1 ) ; 
    A5new1( i , : ) = reshape ( tmp' , 1 , num_swimmers * ( num_ind + num_rr ) ) ; 
end ; 
for i = 1 : num_swimmers ;
    tmp = zeros( num_swimmers , num_ind + num_rr ) ;
    tmp( i , num_ind+num_r1+1:num_ind+num_r1+num_r2 ) = ones ( 1 , num_r2 ) ;
    A5new2( i , : ) = reshape ( tmp' , 1 , num_swimmers * ( num_ind + num_rr ) ) ;
end ;
for i = 1 : num_swimmers ;
    tmp = zeros( num_swimmers , num_ind + num_rr ) ;
    tmp( i , num_ind+num_r1+num_r2+1:num_ind+num_r1+num_r2+num_r3 ) = ones ( 1 , num_r3 ) ;
    A5new3( i , : ) = reshape ( tmp' , 1 , num_swimmers * ( num_ind + num_rr ) ) ;
end ;
A5 = [ A5new1 ; A5new2 ; A5new3 ];
% 6th Constraint - (Logical) Relay teams have exactly four members; 
relay_points = reshape( rel_coeffs' , num_rr , num_swimmers )' ; 
idx = ( relay_points > 0 ) ; 
B6 = zeros( num_rr , 1 ) ; 
A6temp = zeros( num_swimmers , num_ind + num_rr ) ; 
for j = 1 : num_rr; 
    temp = [ 1:num_swimmers ]'(idx(:,j)) ; 
    A6temp( temp(1) , j + num_ind ) = 3 ; 
    for i = 2:size(temp)(1); 
        A6temp( temp(i) , num_ind + j ) = -1 ; 
    end 
end;
for i = 1:num_rr; 
    A6_ = zeros( num_swimmers , num_ind + num_rr ) ; 
    A6_( : , num_ind + i ) = A6temp( : , num_ind + i ) ; 
    A6(i,:) = reshape( A6_' , 1 , num_swimmers * ( num_ind + num_rr ) ) ; 
end;
A6 = [ A6 ; A6 ] ; 
B6 = [ B6 ; B6 ] ; 
Ctype6 = [ char( 'U' * ones( num_rr , 1 ) ) ; char( 'L' * ones( num_rr , 1 ) ) ] ; 
% 7th,8th Constraints - (Logical) Selection coefficients are either 1 or 0; 
B7 = ones( num_swimmers * ( num_ind + num_rr ) , 1 ) ;
Ctype7 = char( 'U' * ones( num_swimmers * ( num_ind + num_rr ) , 1 ) ) ; 
A7 = eye( num_swimmers * ( num_ind + num_rr ) , num_swimmers * ( num_ind + num_rr ) ) ; 
B8 = zeros( num_swimmers * ( num_ind + num_rr ) , 1 ) ; 
Ctype8 = char( 'L' * ones( num_swimmers * ( num_ind + num_rr ) , 1 ) ) ; 
A8 = eye( num_swimmers * ( num_ind + num_rr ) , num_swimmers * ( num_ind + num_rr ) ) ; 
% Variable is an integer; 
Vtype = char( "I" * ones( num_swimmers * ( num_ind + num_rr ) , 1 ) ) ; 
sense = -1 ; 
% Bounds; 
lb = zeros( num_swimmers * ( num_ind + num_rr ) , 1 ); 
ub = Inf * ones( num_swimmers * ( num_ind + num_rr ) , 1 ); 
% Combine; 
A = [ A1 ; A2 ; A3 ; A4 ; A5 ; A6 ; A7 ; A8 ] ; 
B = [ B1 ; B2 ; B3 ; B4 ; B5 ; B6 ; B7 ; B8 ] ; 
Ctype = [ Ctype1 ; Ctype2 ; Ctype3 ; Ctype4 ; Ctype5 ; Ctype6 ; Ctype7 ; Ctype8 ] ; 
cprime = horzcat( reshape( ind_coeffs , num_ind , num_swimmers )' , 1/4*reshape( rel_coeffs' , num_rr , num_swimmers )' ) ;
c = reshape( cprime' , 1 , num_swimmers * ( num_ind + num_rr ) )  ;
[ xopt , zmx ] = glpk( c , A , B , lb , ub , Ctype , Vtype , sense );
xopt , zmx