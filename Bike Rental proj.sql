CREATE SCHEMA IF NOT EXISTS `CECS535Project`;
USE `CECS535Project`;
CREATE USER 'cecs535'@'localhost' IDENTIFIED BY 'taforever';
GRANT ALL PRIVILEGES ON `CECS535Project`.* TO 'cecs535'@'localhost';
CREATE TABLE IF NOT EXISTS `Customers` (
	cid integer,
    cname varchar(256),
    caddress varchar(256),
    city varchar(64),
    zip char(5),
    state char(2),
    `credit-card` char(16),
    PRIMARY KEY(cid)
);
CREATE TABLE IF NOT EXISTS `Bikes`(
	bnumber INTEGER,
    bmake VARCHAR(64),
    bcolor VARCHAR(8),
    `year` integer,
    PRIMARY KEY(bnumber)
);
CREATE TABLE IF NOT EXISTS `Racks`(
	rid integer,
    rlocation varchar(256),
    `num-holds` integer,
    primary key(rid)
);
CREATE TABLE IF NOT EXISTS `Available`(
	bnumber integer,
    `rack-id` integer,
    primary key(bnumber),
    foreign key(bnumber) references Bikes(bnumber),
    foreign key(`rack-id`) references Racks(rid)
);
CREATE TABLE IF NOT EXISTS `Rentals`(
	bnumber integer,
    `cust-id` integer,
    src integer,
    `date` DATE,
    `time` TIME,
    primary key(bnumber, `cust-id`, `date`,`time`),
    foreign key(bnumber) references Bikes(bnumber),
    foreign key(`cust-id`) references Customers(cid),
    foreign key(src) references Racks(rid)
);
CREATE TABLE IF NOT EXISTS `Trips`(
	bnumber integer,
    cid integer,
    `init-date` date,
    `init-time` time,
    `end-date` date,
    `end-time` time,
    `origin-rack` integer,
    `destination-rack` integer,
    cost decimal,
	primary key(bnumber,cid,`init-date`,`init-time`),
    foreign key(`bnumber`) references Bikes(bnumber),
    foreign key(`cid`) references Customers(cid),
    foreign key(`origin-rack`) references Racks(rid),
    foreign key(`destination-rack`) references Racks(rid)
);
CREATE TABLE IF NOT EXISTS `BIKEPROFILE`(
	bikeid integer primary key,
    total time
);

delimiter //
DROP TRIGGER IF EXISTS `cecs535project`.`bikes_AFTER_INSERT`;//
CREATE DEFINER=`root`@`localhost` TRIGGER `bikes_AFTER_INSERT` after INSERT ON `Bikes` FOR EACH ROW BEGIN
	DECLARE finished INTEGER DEFAULT 0;
    declare rid integer;
    declare `num-holds` integer;
    declare rlocation varchar(256);
    declare num_bikes integer;
    declare min_num_bikes integer;
    declare rand integer;
    declare rid_min_num_bikes integer;
    declare racks_curs cursor for (select * from Racks);
    DECLARE CONTINUE HANDLER 
        FOR NOT FOUND SET finished = 1;
	OPEN racks_curs;
    set min_num_bikes = null;
    set rid_min_num_bikes = null;
    getRack: LOOP
		FETCH racks_curs INTO rid,rlocation,`num-holds`;
		IF finished = 1 THEN 
			LEAVE getRack;
		END IF;
        set num_bikes = (select count(*) from Available where `rack-id` = rid);
        if num_bikes < `num-holds` then
			if min_num_bikes is null or min_num_bikes > num_bikes then
				set min_num_bikes = num_bikes;
                set rid_min_num_bikes = rid;
			elseif min_num_bikes = num_bikes then
				set min_num_bikes = num_bikes;
				set rand = floor(rand(current_timestamp))%100;
                if rand < 50 then
					set rid_min_num_bikes = rid;
                end if;
            end if;
        end if;
	END LOOP getRack;
    if rid_min_num_bikes is not null then
		insert into Available values(NEW.bnumber,rid_min_num_bikes);
	else
		signal SQLSTATE '45000' SET MESSAGE_TEXT = 'no racks available';
    end if;
    close racks_curs;
END//
DROP TRIGGER IF EXISTS `cecs535project`.`BIKES_BEFORE_DELETE`;//
CREATE DEFINER=`root`@`localhost` TRIGGER `BIKES_BEFORE_DELETE` before DELETE ON `Bikes` FOR EACH ROW BEGIN
	declare num_rentals integer;
    set num_rentals = (select count(*) from rentals where bnumber = OLD.bnumber);
    if num_rentals = 0 then
		delete from Available where bnumber = OLD.bnumber;
	else
		signal sqlstate '46000'  SET MESSAGE_TEXT = 'this Bike is in use';
    end if;
end;//
DROP TRIGGER IF EXISTS `cecs535project`.`TRIPS_AFTER_INSERT`;//
CREATE DEFINER=`root`@`localhost` TRIGGER `TRIPS_AFTER_INSERT` after insert on `Trips` for each row begin
	declare bike_profile_val integer;
    set bike_profile_val = (select count(*) from BIKEPROFILE where bikeid = NEW.bnumber);
    if bike_profile_val = 0 then
		insert into BIKEPROFILE values(NEW.bnumber,0);
    end if;
    update BIKEPROFILE set total = total + (timediff(concat(NEW.`end-date`,' ',NEW.`end-time`),concat(NEW.`init-date`,' ',NEW.`init-time`))) 
		where BIKEPROFILE.bikeid = NEW.bnumber;
end;//
delimiter ;
delimiter //
DROP PROCEDURE IF EXISTS `cecs535project`.`StartTrip`;//
create PROCEDURE StartTrip(in bikenum integer,in cid integer)
begin
	declare bikenum_val integer;
    declare cid_val integer;
    declare src integer;
    declare bike_available_val integer;
    set bikenum_val = (select count(*) from Bikes where bnumber = bikenum);
    if bikenum_val = 0 then
		signal sqlstate '47000' SET MESSAGE_TEXT = 'bike not enrolled';
    end if;
    set cid_val = (select count(*) from Customers where Customers.cid = cid);
    if cid_val = 0 then
		signal sqlstate '48000' SET MESSAGE_TEXT = 'Customer not enrolled';
    end if;
    set bike_available_val = (select count(*) from Available where bnumber = bikenum);
    if bike_available_val = 0 then
		signal sqlstate '49000' SET MESSAGE_TEXT = 'bike not available';
    end if;
    set src = (select `rack-id` from Available where bnumber = bikenum);
    delete from Available where bnumber = bikenum;
    insert into Rentals values(bikenum,cid,src,CAST(now() as date),CAST(now() as time));
end;//
DROP PROCEDURE IF EXISTS `cecs535project`.`EndTrip`;//
create PROCEDURE EndTrip(in bikenum integer,in cid integer,in dest integer, in cost decimal)
begin
	declare rental_val integer;
    declare init_date date;
    declare init_time time;
    declare src_var integer;
    declare dest_val integer;
    declare dest_room_val integer;
    set rental_val = (select count(*) from Rentals where bnumber = bikenum and `cust-id` = cid);
    if rental_val = 0 then
		signal sqlstate '50000' SET MESSAGE_TEXT = 'the customer did not rent the bike';
    end if;
    set dest_val = (select count(*) from Racks where rid = dest);
    if dest_val = 0 then
		signal sqlstate '51000' SET MESSAGE_TEXT = 'the destination is not registered';
    end if;
    set dest_room_val = (select count(*) from Available where `rack-id` = dest);
    if dest_room_val >= (select `num-holds` from Racks where rid = dest) then
		signal sqlstate '51000' SET MESSAGE_TEXT = 'the destination rack has no more room';
    end if;
    set init_date = (select `date` from Rentals where bnumber = bikenum and `cust-id` = cid);
    set init_time = (select `time` from Rentals where bnumber = bikenum and `cust-id` = cid);
    set src_var = (select `src` from Rentals where bnumber = bikenum and `cust-id` = cid);
    delete from Rentals where bnumber = bikenum and `cust-id` = cid;
    insert into Trips values(bikenum,cid,init_date,init_time,CAST(now() as date),CAST(now() as time),src_var,dest,cost);
end//
delimiter ;

