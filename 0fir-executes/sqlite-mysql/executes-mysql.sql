BEGIN TRANSACTION;
CREATE TABLE "executes" (
	`id`	INTEGER,
	`map`	varchar(32) NOT NULL,
	`name`	varchar(64) NOT NULL,
	`site`	INTEGER,
	PRIMARY KEY(id)
);
INSERT INTO `executes` (id,map,name,site) VALUES (2,'de_mirage','A Execute',0),
 (3,'de_mirage','Split B',1),
 (4,'de_mirage','B Execute',1),
 (5,'de_mirage','A Fast Plant',0),
 (6,'de_mirage','Split A',0);
COMMIT;
