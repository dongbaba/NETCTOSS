--建立帐务信息表account--
create table account(
id number(9) constraint account_id_pk primary key,
recommender_id number(9) constraint account_recommender_fk references account(id),
login_name varchar2(30) not null constraint account_login_name_uk unique,
login_passwd varchar2(8) not null,
status char(1) not null constraint account_status_ck check(status in (0,1,2)),
create_date date default sysdate,
pause_date date,
close_date date,
real_name varchar2(20) not null,
idcard_no char(18) not null constraint account_indcard_no_uk unique,
birthdate date,
gender char(1) not null constraint account_gender_ck check(gender in (0,1)),
occupation varchar2(50),
telephone varchar2(15),
email varchar2(50),
mailaddress varchar2(50),
zipcode char(6),
qq varchar2(15),
last_login_time date,
last_login_ip varchar2(15));

create sequence account_seq
start with 1000;

--建立资费信息表cost--
create table cost(
id number(4) constraint cost_id_pk primary key,
name varchar2(50) not null,
cost_type number,
base_duration number(11),
base_cost number(7,2),
unit_cost number(7,4),
status char(1) not null constraint cost_status_ck check(status in (0,1,2)),
descr varchar2(100),
create_time date default sysdate,
start_time date);

create sequence cost_seq
start with 1;

--建立服务器信息表host--
create table host(
id varchar2(15) constraint host_id_pk primary key,
name varchar2(20) not null,
location varchar2(20));


--建立业务信息表service--
create table service(
id number(10) constraint service_id_pk primary key,
account_id number(9) not null constraint service_account_id_fk references account(id),
unix_host varchar2(15) not null,
os_username varchar2(8) not null,
constraint sjl_service_host_username_uk unique(unix_host,os_username),
login_passwd varchar2(8) not null,
status char(1) not null constraint service_status_ck check(status in (0,1,2)),
create_date date default sysdate,
pause_date date,
close_date date,
cost_id number(4) not null constraint service_cost_id_fk references cost(id));

create sequence service_seq
start with 2009;

--建立业务详单表service_detail--
create table service_detail(
id number(11) constraint service_detail_pk primary key,
service_id number(10) not null constraint sd_service_id_fk references service(id),
client_host varchar2(15),
os_username varchar2(8),
pid number(11),
login_time date,
logout_time date,
duration number(20,9),
cost number(20,6));

--建立序列表service_detail_seq--
create sequence  service_detail_seq
increment by 1
start with 1;

--建立年龄分段信息表age_segment--
create table age_segment(
id number(1) constraint age_segment_id_pk primary key,
name varchar2(20) not null,
lowage number(2),
hiage number(2)
);

create sequence age_segment_seq
start with 1;

--建立时长信息表--
create table month_duration(
service_id number(10),
month_id char(6),
service_detail_id number(10),
sofar_duration number(11));

--建立帐单信息表bill--
create table bill(
id number(11) constraint bill_id_pk primary key,
account_id number(9) not null constraint bill_aid_fk references account(id),
bill_month char(6) not null,
cost number(13,2) not null,
payment_mode char(1) constraint bill_paymode_ck check (payment_mode in (0,1,2,3)),
pay_state char(1) default 0 constraint bill_ps_ck check(pay_state in (0,1)));

create sequence bill_seq;

--建立帐单条目表bill_item--
create table bill_item(
item_id number(11) constraint bill_item_itid_pk primary key,
bill_id number(11) not null constraint bill_item_billid_fk references bill(id),
service_id number(10) not null constraint bill_item_sid_fk references service(id),
cost number(13,2));

create sequence bill_item_seq;

--建立角色表role_info--
create table role_info(
id number(11) constraint role_info_id_pk primary key,
name varchar(20));

create sequence role_info_seq;

--建立角色权限表role_privilege--
create table role_privilege(
role_id number(4),
pribilege_id number(4),
constraint role_privilege_id_pk primary key(role_id,pribilege_id));

--建立管理员表admin_info--
create table admin_info(
id number(4) constraint admin_info_id_pk primary key,
admin_code varchar(30) not null constraint admin_info_ac_uk unique,
password varchar(8) not null,
name varchar(20) not null,
telephone varchar(15),
email varchar2(50),
enrolldate date not null);

create sequence admin_info_seq;

--建立管理员角色表admin_role--
create table admin_role(
admin_id number(4) constraint admin_role_aid_fk references admin_info(id),
role_id number(4) constraint admin_role_rid_fk references role_info(id),
constraint admin_role_id_pk primary key (admin_id,role_id));


--建立月底修改记录表--
create table SERVICE_UPDATE_BAK(
ID number(9) primary key,
SERVICE_ID number(9),
UNIX_HOST varchar2(15),
OS_USERNAME varchar2(8),
COST_ID number(4),
CREAT_TIME date
);

create sequence SERVICE_UPDATE_BAK_SEQ;

--调用该存储过程月底修改资费
CREATE OR REPLACE PROCEDURE UPDATE_SERVICE_COST
  IS
  BEGIN
    MERGE INTO service s
    USING service_update_bak s_bak
    ON (s.id = s_bak.service_id)
    WHEN MATCHED THEN
    UPDATE SET
   s.cost_id=s_bak.cost_id;
   DELETE FROM SERVICE_UPDATE_BAK;
   COMMIT;
 END;
--在插入业务详单信息时，计算需要计费的每条详单的费用,按照费用类型进行的分类，套餐类型和实时计费。包月类型无业务详单费用
CREATE OR REPLACE TRIGGER gen_fee
BEFORE INSERT ON service_detail
FOR EACH ROW
DECLARE
  TYPE t_cost IS RECORD
         (base_cost cost.base_cost%TYPE,
          base_duration cost.base_duration%TYPE,
          unit_cost cost.unit_cost%TYPE,
          cost_type cost.cost_type%TYPE);
  v_cost t_cost;
  v_sofar_duration month_duration.sofar_duration%TYPE;
  v_temp_duration month_duration.sofar_duration%TYPE;
  v_duration service_detail.duration%TYPE;
  v_count number(20);
  BEGIN
    -- 定位service_id的资费标准
    SELECT base_cost,base_duration,unit_cost,cost_type INTO v_cost FROM cost c JOIN service s ON s.cost_id = c.id AND s.id  = :new.service_id;
   --2表示资费类型为套餐
   IF v_cost.cost_type=2   THEN
      --查询为了判断month_duration表中是否有当前月的数据
      SELECT count(*) into v_count FROM month_duration WHERE service_id = :new.service_id AND month_id = TO_CHAR(:new.logout_time,'yyyymm');
      --在month_duration表中已经存在当前月的数据
      IF v_count>0 THEN
         -- 获得service_id当月累计时长
         SELECT sofar_duration INTO v_sofar_duration FROM month_duration WHERE service_id = :new.service_id AND month_id = TO_CHAR(:new.logout_time,'yyyymm');
          -- 到目前为止的累计时长
          v_temp_duration:=v_sofar_duration;
          --加上当前这次的duration
          v_sofar_duration := v_sofar_duration + :new.duration;
          -- 和基本时长的差
         v_duration := v_sofar_duration - v_cost.base_duration*60*60;
         --当前插入的service_detail的数据部分时长大于包月时长
         IF v_duration > 0 AND v_cost.base_duration*60*60> v_temp_duration THEN
            :new.cost := v_cost.unit_cost    * v_duration/3600;
          --当前插入的service_detail的数据全部时长大于包月时长
         ELSIF v_duration > 0 AND v_cost.base_duration*60*60<= v_temp_duration THEN
           :new.cost :=v_cost.unit_cost*:new.duration/3600;   
         END IF;
         --使month_duration表中的当前月时长进行累加
         UPDATE month_duration SET sofar_duration=v_sofar_duration WHERE service_id = :new.service_id AND month_id = TO_CHAR(:new.logout_time,'yyyymm') ;
      --在month_duration表中已经不存在当前月的数据
      ELSE
        v_sofar_duration := :new.duration;
       INSERT  INTO month_duration(service_id,month_id,sofar_duration)
       VALUES (:new.service_id,TO_CHAR(:new.logout_time,'yyyymm'),v_sofar_duration); 
     END IF;
   --1表示资费类型为计时费用
   ELSIF v_cost.cost_type=3  THEN
      :new.cost :=v_cost.unit_cost*(:new.duration/3600); 
   END IF;    
  END;

--以下为生产账单所需内容
--用临时表技术生成账单编号表，用于保存BILL_ID(账单ID)，ACCOUNT_ID（帐务ID），BILL_MONTH（账单月）
CREATE GLOBAL TEMPORARY TABLE BILL_CODE
(BILL_ID  		NUMBER(11),
 ACCOUNT_ID 	NUMBER(9),
 BILL_MONTH 	CHAR(6)
) On COMMIT PRESERVE ROWS;
 
 --用临时表技术，临时存储BILL_ITEM信息
CREATE GLOBAL TEMPORARY TABLE BILL_ITEM_TEMP
(ITEM_ID		NUMBER(11),
 BILL_ID 		NUMBER(11),
 SERVICE_ID 	NUMBER(10) NOT NULL,
 COST 		NUMBER(13,2)
) On COMMIT PRESERVE ROWS;

----------------自动产生主键的trigger----------------
------BILLL_CODE表中的BILL_ID自动生成,创建触发器产生主键
CREATE OR REPLACE TRIGGER GEN_BILL_ID
BEFORE INSERT ON BILL_CODE
FOR EACH ROW
DECLARE
BEGIN
      SELECT BILL_SEQ.NEXTVAL INTO :NEW.BILL_ID FROM DUAL;
END;

----BILL_ITEM表中的ITEM_ID自动生成,创建触发器产生主键
CREATE OR REPLACE TRIGGER GEN_ITEM_ID
BEFORE INSERT ON BILL_ITEM
FOR EACH ROW
DECLARE
BEGIN
      SELECT BILL_ITEM_SEQ.NEXTVAL INTO :NEW.ITEM_ID FROM DUAL;
END;

 --使用存储过程向账单和账单条目表中添加数据。
CREATE OR REPLACE  PROCEDURE GBILL_ALL
  IS
  BEGIN
    --向临时表BILL_CODE表中插入数据
    INSERT INTO BILL_CODE(ACCOUNT_ID,BILL_MONTH)
      SELECT   ID,
        TO_CHAR(ADD_MONTHS(SYSDATE,-1),'YYYYMM') 
      FROM ACCOUNT;
    --向临时表BILL_ITEM_TEMP中插入数据
    INSERT INTO BILL_ITEM_TEMP(BILL_ID,SERVICE_ID,COST)
      SELECT  B.BILL_ID,A.SERVICE_ID,
          A.COST + NVL(C.BASE_COST,0)
      FROM BILL_CODE B JOIN
        (SELECT  MAX(S.ACCOUNT_ID) ACCOUNT_ID,
          D.SERVICE_ID,
          MAX(S.COST_ID) COST_ID,
          SUM(COST) COST
        FROM SERVICE_DETAIL D  JOIN SERVICE S
        ON D.SERVICE_ID = S.ID
        AND  TO_CHAR(D.LOGOUT_TIME,'YYYYMM') = 
                            TO_CHAR(ADD_MONTHS(SYSDATE,-1),'YYYYMM')
        GROUP BY D.SERVICE_ID
        ) A
        ON B.ACCOUNT_ID = A.ACCOUNT_ID
        JOIN COST C
      ON A.COST_ID = C.ID;  
      --向表BILL中插入数据
      INSERT INTO BILL(ID,ACCOUNT_ID,BILL_MONTH,COST)
      SELECT   BC.BILL_ID,
        MAX(BC.ACCOUNT_ID),
        MAX(BC.BILL_MONTH),
        SUM(I.COST)
      FROM BILL_CODE BC JOIN bill_item_temp I
			ON BC.BILL_ID = I.BILL_ID
			GROUP BY BC.BILL_ID;
      --向表BILL_ITEM中插入数据
      INSERT INTO BILL_ITEM(BILL_ID,SERVICE_ID,COST)
      SELECT  B.BILL_ID,A.SERVICE_ID,
          A.COST + NVL(C.BASE_COST,0)
      FROM BILL_CODE B JOIN
        (SELECT  MAX(S.ACCOUNT_ID) ACCOUNT_ID,
          D.SERVICE_ID,
          MAX(S.COST_ID) COST_ID,
          SUM(COST) COST
        FROM SERVICE_DETAIL D  JOIN SERVICE S
        ON D.SERVICE_ID = S.ID
        AND  TO_CHAR(D.LOGOUT_TIME,'YYYYMM') = 
                            TO_CHAR(ADD_MONTHS(SYSDATE,-1),'YYYYMM')
        GROUP BY D.SERVICE_ID
        ) A
        ON B.ACCOUNT_ID = A.ACCOUNT_ID
        JOIN COST C
      ON A.COST_ID = C.ID;
  COMMIT;
 END;
 
 
 ----------部分测试数据
 
--插入account表数据--
alter session set nls_date_format = 'yyyy-mm-dd';
insert into account (id, recommender_id, login_name, login_passwd, status, create_date, real_name, idcard_no, telephone, gender) values(1005, null, 'taiji001', '256528', 1, '2008-03-15', 'zhangsanfeng', '410381194302256528', '13669351234', 0);
insert into account (id, recommender_id, login_name, login_passwd, status, create_date, real_name, idcard_no, telephone, gender) values(1010, null, 'xl18z60', '190613', 1, '2009-06-10', 'guojing', '330682196903190613', '13338924567', 0);
insert into account (id, recommender_id, login_name, login_passwd, status, create_date, real_name, idcard_no, telephone, gender) values(1011, 1010, 'dgbf70', '270429', 1, '2009-03-01', 'huangrong', '330902197108270429', '13637811357',1);
insert into account (id, recommender_id, login_name, login_passwd, status, create_date, real_name, idcard_no, telephone, gender) values(1015, 1005, 'mjjzh64', '041115', 1, '2010-03-12', 'zhangwuji', '610121198906041115', '13572952468', 0);
insert into account (id, recommender_id, login_name, login_passwd, status, create_date, real_name, idcard_no, telephone, gender) values(1018, 1011, 'jmdxj00', '010322', 1, '2011-06-01', 'guofurong', '350581200201010322', '18617832562' , 1);
insert into account (id, recommender_id, login_name, login_passwd, status, create_date, real_name, idcard_no, telephone, gender) values(1019, 1011, 'ljxj90', '310346', 1, '2012-02-01', 'luwushuang', '320211199307310346', '13186454984',1 );
insert into account (id, recommender_id, login_name, login_passwd, status, create_date, real_name, idcard_no, telephone, gender) values(1020, null, 'kxhxd20', '121155', 1, '2012-02-20', 'weixiaobao', '321022200010012115', '13953410078', 0);
commit;


--插入cost信息--
insert into cost values (1,'5.9元套餐',1,20,5.9,0.4,0,'5.9元20小时/月,超出部分0.4元/时',default,null);
insert into cost values (2,'6.9元套餐',1,40,6.9,0.3,0,'6.9元40小时/月,超出部分0.3元/时',default,null);
insert into cost values (3,'8.5元套餐',1,100,8.5,0.2,0,'8.5元100小时/月,超出部分0.2元/时',default,null);
insert into cost values (4,'10.5元套餐',1,200,10.5,0.1,0,'10.5元200小时/月,超出部分0.1元/时',default,null);
insert into cost values (5,'计时收费',2,null,null,0.5,0,'0.5元/时,不使用不收费',default,null);
insert into cost values (6,'包月',0,null,20,null,0,'每月20元,不限制使用时间',default,null);
commit;

--插入host信息--
insert into host values ('192.168.0.26','sunv210','beijing');
insert into host values('192.168.0.20','sun-server','beijing');
insert into host values ('192.168.0.23','sun280','beijing');
insert into host values ('192.168.0.200','ultra10','beijing');
commit;

--插入业务信息表信息--
alter session set nls_date_format = 'yyyy mm dd hh24:mi:ss';
insert into service values (2001,1010,'192.168.0.26','guojing','guo1234',0,'2009 03 10 10:00:00',null,null,1);
insert into service values (2002,1011,'192.168.0.26','huangr','huang234',0,'2009 03 01 15:30:05',null,null,1);
insert into service values (2003,1011,'192.168.0.20','huangr','huang234',0,'2009 03 01 15:30:10',null,null,3);
insert into service values (2004,1011,'192.168.0.23','huangr','huang234',0,'2009 03 01 15:30:15',null,null,6);
insert into service values (2005,1019,'192.168.0.26','luwsh','luwu2345',0,'2012 02 10 23 :50:55',null,null,4);
insert into service values (2006,1019,'192.168.0.20','luwsh','luwu2345',0,'2012 02 10 00 :00:00',null,null,5);
insert into service values (2007,1020,'192.168.0.20','weixb','wei12345',0,'2012 02 10 11:05:20',null,null,6);
insert into service values (2008,1010,'192.168.0.20','guojing','guo09876',0,'2012 02 11 12:05:21',null,null,6);
commit;

--插入age_segment表信息--
insert into age_segment values (0,'少年逆反期',11,14);
insert into age_segment values (1,'少年成长期',15,17);
insert into age_segment values (2,'青年青春期',18,28);
insert into age_segment values (3,'青年成熟期',29,40);
insert into age_segment values (4,'中年壮实期',41,48);
insert into age_segment values (5,'中年稳健期',49,55);
insert into age_segment values (6,'中年稳健期',56,65);
insert into age_segment values (7,'老年初老期',66,72);
commit;
--admin_info--
insert into admin_info
 values(1001,'admin','111111','lily','13688997766','shiyl@sin.com'
,to_date('2013-05-22','yyyy-mm-dd'));
insert into admin_info
values(1002,'lily','lily123','lily','13688997766',
'shiyl@sin.com',to_date('2013-05-22','yyyy-mm-dd'));

--role_info--
insert into role_info values (1,'超级管理员');
insert into role_info values (2,'资费管理员');

--admin_role--
insert into admin_role values (1001,1);
insert into admin_role values (1002,2);

--role_privilege--
insert into role_privilege values (1,1);
insert into role_privilege values (1,2);
insert into role_privilege values (1,3);
insert into role_privilege values (1,4);
insert into role_privilege values (1,5);
insert into role_privilege values (1,6);
insert into role_privilege values (1,7);
insert into role_privilege values (2,3);

--service_detail--
insert into service_detail values (service_detail_seq.nextval,2001,'192.168.0.1','guojing',123,to_date('2013-05-05 20:20:00','yyyy-mm-dd hh24:mi:ss'),to_date('2013-05-05 21:20:00','yyyy-mm-dd hh24:mi:ss'),3600,0);
insert into service_detail values (service_detail_seq.nextval,2001,'192.168.0.1','guojing',123,to_date('2013-05-06 10:20:00','yyyy-mm-dd hh24:mi:ss'),to_date('2013-05-06 20:20:00','yyyy-mm-dd hh24:mi:ss'),36000,0);
insert into service_detail values (service_detail_seq.nextval,2001,'192.168.0.1','guojing',123,to_date('2013-05-07 10:20:00','yyyy-mm-dd hh24:mi:ss'),to_date('2013-05-07 20:20:00','yyyy-mm-dd hh24:mi:ss'),36000,0);
insert into service_detail values (service_detail_seq.nextval,2001,'192.168.0.1','guojing',123,to_date('2013-05-08 10:20:00','yyyy-mm-dd hh24:mi:ss'),to_date('2013-05-08 12:55:00','yyyy-mm-dd hh24:mi:ss'),9300,0);
insert into service_detail values (service_detail_seq.nextval,2001,'192.168.0.1','guojing',123,to_date('2013-05-08 18:20:00','yyyy-mm-dd hh24:mi:ss'),to_date('2013-05-08 22:52:00','yyyy-mm-dd hh24:mi:ss'),16320,0);
insert into service_detail values (service_detail_seq.nextval,2001,'192.168.0.1','guojing',123,to_date('2013-05-09 10:20:00','yyyy-mm-dd hh24:mi:ss'),to_date('2013-05-09 14:52:00','yyyy-mm-dd hh24:mi:ss'),16320,0);
insert into service_detail values (service_detail_seq.nextval,2001,'192.168.0.1','guojing',123,to_date('2013-05-09 11:20:00','yyyy-mm-dd hh24:mi:ss'),to_date('2013-05-09 13:22:00','yyyy-mm-dd hh24:mi:ss'),7320,0);
insert into service_detail values (service_detail_seq.nextval,2001,'192.168.0.1','guojing',123,to_date('2013-05-10 16:20:00','yyyy-mm-dd hh24:mi:ss'),to_date('2013-05-10 18:52:00','yyyy-mm-dd hh24:mi:ss'),9120,0);
insert into service_detail values (service_detail_seq.nextval,2001,'192.168.0.1','guojing',123,to_date('2013-05-10 20:20:00','yyyy-mm-dd hh24:mi:ss'),to_date('2013-05-10 22:52:00','yyyy-mm-dd hh24:mi:ss'),9120,0);
insert into service_detail values (service_detail_seq.nextval,2001,'192.168.0.1','guojing',123,to_date('2013-05-11 18:20:00','yyyy-mm-dd hh24:mi:ss'),to_date('2013-05-11 22:52:00','yyyy-mm-dd hh24:mi:ss'),16320,0);
-----
insert into service_detail values (service_detail_seq.nextval,2008,'192.168.0.1','guojing',123,to_date('2013-05-05 20:20:00','yyyy-mm-dd hh24:mi:ss'),to_date('2013-05-05 21:20:00','yyyy-mm-dd hh24:mi:ss'),3600,0);
insert into service_detail values (service_detail_seq.nextval,2008,'192.168.0.1','guojing',123,to_date('2013-05-06 10:20:00','yyyy-mm-dd hh24:mi:ss'),to_date('2013-05-06 20:20:00','yyyy-mm-dd hh24:mi:ss'),36000,0);
insert into service_detail values (service_detail_seq.nextval,2008,'192.168.0.1','guojing',123,to_date('2013-05-07 10:20:00','yyyy-mm-dd hh24:mi:ss'),to_date('2013-05-07 20:20:00','yyyy-mm-dd hh24:mi:ss'),36000,0);
insert into service_detail values (service_detail_seq.nextval,2008,'192.168.0.1','guojing',123,to_date('2013-05-08 10:20:00','yyyy-mm-dd hh24:mi:ss'),to_date('2013-05-08 12:55:00','yyyy-mm-dd hh24:mi:ss'),9300,0);
insert into service_detail values (service_detail_seq.nextval,2008,'192.168.0.1','guojing',123,to_date('2013-05-08 18:20:00','yyyy-mm-dd hh24:mi:ss'),to_date('2013-05-08 22:52:00','yyyy-mm-dd hh24:mi:ss'),16320,0);
insert into service_detail values (service_detail_seq.nextval,2008,'192.168.0.1','guojing',123,to_date('2013-05-09 10:20:00','yyyy-mm-dd hh24:mi:ss'),to_date('2013-05-09 14:52:00','yyyy-mm-dd hh24:mi:ss'),16320,0);
insert into service_detail values (service_detail_seq.nextval,2008,'192.168.0.1','guojing',123,to_date('2013-05-09 11:20:00','yyyy-mm-dd hh24:mi:ss'),to_date('2013-05-09 13:22:00','yyyy-mm-dd hh24:mi:ss'),7320,0);
insert into service_detail values (service_detail_seq.nextval,2008,'192.168.0.1','guojing',123,to_date('2013-05-10 16:20:00','yyyy-mm-dd hh24:mi:ss'),to_date('2013-05-10 18:52:00','yyyy-mm-dd hh24:mi:ss'),9120,0);
insert into service_detail values (service_detail_seq.nextval,2008,'192.168.0.1','guojing',123,to_date('2013-05-10 20:20:00','yyyy-mm-dd hh24:mi:ss'),to_date('2013-05-10 22:52:00','yyyy-mm-dd hh24:mi:ss'),9120,0);
insert into service_detail values (service_detail_seq.nextval,2008,'192.168.0.1','guojing',123,to_date('2013-05-11 18:20:00','yyyy-mm-dd hh24:mi:ss'),to_date('2013-05-11 22:52:00','yyyy-mm-dd hh24:mi:ss'),16320,0);

insert into service_detail values (service_detail_seq.nextval,2002,'192.168.0.1','huangr',123,to_date('2013-04-05 20:20:00','yyyy-mm-dd hh24:mi:ss'),to_date('2013-04-05 21:20:00','yyyy-mm-dd hh24:mi:ss'),3600,0);
insert into service_detail values (service_detail_seq.nextval,2002,'192.168.0.1','huangr',123,to_date('2013-04-06 10:20:00','yyyy-mm-dd hh24:mi:ss'),to_date('2013-04-06 20:20:00','yyyy-mm-dd hh24:mi:ss'),36000,0);
insert into service_detail values (service_detail_seq.nextval,2002,'192.168.0.1','huangr',123,to_date('2013-04-07 10:20:00','yyyy-mm-dd hh24:mi:ss'),to_date('2013-04-07 20:20:00','yyyy-mm-dd hh24:mi:ss'),36000,0);
insert into service_detail values (service_detail_seq.nextval,2002,'192.168.0.1','huangr',123,to_date('2013-04-08 10:20:00','yyyy-mm-dd hh24:mi:ss'),to_date('2013-04-08 12:55:00','yyyy-mm-dd hh24:mi:ss'),9300,0);
insert into service_detail values (service_detail_seq.nextval,2002,'192.168.0.1','huangr',123,to_date('2013-04-08 18:20:00','yyyy-mm-dd hh24:mi:ss'),to_date('2013-04-08 22:52:00','yyyy-mm-dd hh24:mi:ss'),16320,0);
insert into service_detail values (service_detail_seq.nextval,2002,'192.168.0.1','huangr',123,to_date('2013-04-09 10:20:00','yyyy-mm-dd hh24:mi:ss'),to_date('2013-04-09 14:52:00','yyyy-mm-dd hh24:mi:ss'),16320,0);
insert into service_detail values (service_detail_seq.nextval,2002,'192.168.0.1','huangr',123,to_date('2013-04-09 11:20:00','yyyy-mm-dd hh24:mi:ss'),to_date('2013-04-09 13:22:00','yyyy-mm-dd hh24:mi:ss'),7320,0);
insert into service_detail values (service_detail_seq.nextval,2002,'192.168.0.1','huangr',123,to_date('2013-04-10 16:20:00','yyyy-mm-dd hh24:mi:ss'),to_date('2013-04-10 18:52:00','yyyy-mm-dd hh24:mi:ss'),9120,0);
insert into service_detail values (service_detail_seq.nextval,2002,'192.168.0.1','huangr',123,to_date('2013-04-10 20:20:00','yyyy-mm-dd hh24:mi:ss'),to_date('2013-04-10 22:52:00','yyyy-mm-dd hh24:mi:ss'),9120,0);
insert into service_detail values (service_detail_seq.nextval,2002,'192.168.0.1','huangr',123,to_date('2013-04-11 18:20:00','yyyy-mm-dd hh24:mi:ss'),to_date('2013-04-11 22:52:00','yyyy-mm-dd hh24:mi:ss'),16320,0);

insert into service_detail values (service_detail_seq.nextval,2008,'192.168.0.1','guojing',123,to_date('2013-04-05 20:20:00','yyyy-mm-dd hh24:mi:ss'),to_date('2013-04-05 21:20:00','yyyy-mm-dd hh24:mi:ss'),3600,0);
insert into service_detail values (service_detail_seq.nextval,2008,'192.168.0.1','guojing',123,to_date('2013-04-06 10:20:00','yyyy-mm-dd hh24:mi:ss'),to_date('2013-04-06 20:20:00','yyyy-mm-dd hh24:mi:ss'),36000,0);
insert into service_detail values (service_detail_seq.nextval,2008,'192.168.0.1','guojing',123,to_date('2013-04-07 10:20:00','yyyy-mm-dd hh24:mi:ss'),to_date('2013-04-07 20:20:00','yyyy-mm-dd hh24:mi:ss'),36000,0);
insert into service_detail values (service_detail_seq.nextval,2008,'192.168.0.1','guojing',123,to_date('2013-04-08 10:20:00','yyyy-mm-dd hh24:mi:ss'),to_date('2013-04-08 12:55:00','yyyy-mm-dd hh24:mi:ss'),9300,0);
insert into service_detail values (service_detail_seq.nextval,2008,'192.168.0.1','guojing',123,to_date('2013-04-08 18:20:00','yyyy-mm-dd hh24:mi:ss'),to_date('2013-04-08 22:52:00','yyyy-mm-dd hh24:mi:ss'),16320,0);
insert into service_detail values (service_detail_seq.nextval,2008,'192.168.0.1','guojing',123,to_date('2013-04-09 10:20:00','yyyy-mm-dd hh24:mi:ss'),to_date('2013-04-09 14:52:00','yyyy-mm-dd hh24:mi:ss'),16320,0);
insert into service_detail values (service_detail_seq.nextval,2008,'192.168.0.1','guojing',123,to_date('2013-04-09 11:20:00','yyyy-mm-dd hh24:mi:ss'),to_date('2013-04-09 13:22:00','yyyy-mm-dd hh24:mi:ss'),7320,0);
insert into service_detail values (service_detail_seq.nextval,2008,'192.168.0.1','guojing',123,to_date('2013-04-10 16:20:00','yyyy-mm-dd hh24:mi:ss'),to_date('2013-04-10 18:52:00','yyyy-mm-dd hh24:mi:ss'),9120,0);
insert into service_detail values (service_detail_seq.nextval,2008,'192.168.0.1','guojing',123,to_date('2013-04-10 20:20:00','yyyy-mm-dd hh24:mi:ss'),to_date('2013-04-10 22:52:00','yyyy-mm-dd hh24:mi:ss'),9120,0);
insert into service_detail values (service_detail_seq.nextval,2008,'192.168.0.1','guojing',123,to_date('2013-04-11 18:20:00','yyyy-mm-dd hh24:mi:ss'),to_date('2013-04-11 22:52:00','yyyy-mm-dd hh24:mi:ss'),16320,0);

insert into service_detail values (service_detail_seq.nextval,2004,'192.168.0.1','huangr',123,to_date('2013-04-05 20:20:00','yyyy-mm-dd hh24:mi:ss'),to_date('2013-04-05 21:20:00','yyyy-mm-dd hh24:mi:ss'),3600,0);
insert into service_detail values (service_detail_seq.nextval,2005,'192.168.0.1','luwsh',123,to_date('2013-04-05 20:20:00','yyyy-mm-dd hh24:mi:ss'),to_date('2013-04-05 21:20:00','yyyy-mm-dd hh24:mi:ss'),3600,0);
insert into service_detail values (service_detail_seq.nextval,2006,'192.168.0.1','luwsh',123,to_date('2013-04-05 20:20:00','yyyy-mm-dd hh24:mi:ss'),to_date('2013-04-05 21:20:00','yyyy-mm-dd hh24:mi:ss'),3600,0);
insert into service_detail values (service_detail_seq.nextval,2007,'192.168.0.1','weixb',123,to_date('2013-04-05 20:20:00','yyyy-mm-dd hh24:mi:ss'),to_date('2013-04-05 21:20:00','yyyy-mm-dd hh24:mi:ss'),3600,0);


