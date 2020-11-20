/******************************************************************************/
/* $Id: step2_Lifetest.sas, 1.1 2019/08/01 17:23:48 lafede Exp $*/
/**/
/* Copyright(c) 2019 SAS Institute Inc., Cary, NC, USA. All Rights Reserved.*/
/**/
/* Name: step2_Lifetest.sas */
/**/
/* Purpose: Automated survival analysis on clinical trial data. Output from proc lifetest created, along with additional variables.
				Code to be deployed in LSAF. */
/**/
/* Author: Laura Federline, Jackie Lanning */
/**/
/* Support: SAS(r) Global Hosting and US Professional Services */
/**/
/* Input: */
/**/
/* Output: sa.&output_data */
/**/
/* Parameters: */
/**/
/* Dependencies/Assumptions: step1_dataPrep.sas has been run */
/**/
/* Usage: SAS 9.4 or later needed */
/**/
/* History:*/
/* ddmmmyyyy userid description (Change Code)*/
/******************************************************************************/

/* Start timer */
%let _timer_start = %sysfunc(datetime());

	
ods select none;

/* Obtain lifetest output */	
	
	*Lifetest on stratified patients;	
	proc sort data=long_target_dm; by target; run;
	
	ods output ProductLimitEstimates=strat_SurvivalPlot;
	proc lifetest data=long_target_dm ;
		by target;
		time &target_start*status(0);
		strata &grouping;
		id usubjid;
	run;
	ods output close;
	
	data lifetest_data;
		length stratum $200;
		set strat_survivalplot (drop=stratum);
		stratum=&grouping;
		drop &grouping;
		label stratum="Stratification";
	run;
	
	
	
/* Adding Benchmark Statistics */
	
	*Obtain total number of patients and number in each strata;
	proc sort data=lifetest_data; by stratum target descending left; run;
	data total_stats;
		set lifetest_data;
		by stratum;
		if first.stratum;
		stratum_total=left;
		keep stratum stratum_total;
	run;
	
	data lifetest_bm;
		merge lifetest_data total_stats;
		by stratum;
	run;
	
	*Add variables for number and percentage of patients who experienced the event within stratums;
	proc freq data=long_target_dm(where=(status=1));
		tables target / out=all_target_num(drop=percent);
		tables &grouping*target / out=stratum_target_num(drop=percent);
	run;
	
	proc sort data=lifetest_bm; by target; run;
	data lifetest_bm;
		merge lifetest_bm all_target_num;
		by target;
		rename count=total_occurences;
	run;
		
	data all_target_num;
		set all_target_num;
		stratum="overall";
	run;
	
	data target_strat_num;
		length stratum $200. ;
		set all_target_num stratum_target_num(rename=(&grouping=stratum)); 
		rename count=stratum_target_number;
	run;
	
	proc sort data=lifetest_bm; by stratum target; run;
	proc sort data=target_strat_num; by stratum target; run;
	data lifetest_bm;
		merge lifetest_bm target_strat_num;
		by stratum target;
		if missing(stratum_target_number) then stratum_target_number=0;
		stratum_target_percent = stratum_target_number/stratum_total;
		label stratum_target_number="Number in stratum that experienced target"
				stratum_target_percent="% of stratum that experienced target"
				total_occurences="Number in study that experienced target";
	run;
	
	
	*Add variable for earliest day target is experienced within stratums;
	proc sort data=lifetest_bm; by stratum target descending left; run;

	proc sort data=long_target_dm; by target &target_start; run;
	data all_earliest;
		set long_target_dm(where=(status=1));
		by target;
		if first.target then do;
			earliest=&target_start;
			stratum="overall";
			output;
		end;
		keep target earliest stratum;
	run;
	
	proc sort data=long_target_dm; by &grouping target &target_start; run;
	data strat_earliest;
		set long_target_dm(where=(status=1));
		by &grouping target;
		if first.target then do;
			earliest=&target_start;
			output;
		end;
		keep &grouping target earliest;
	run;

	data earliest;
		length stratum $200. ;
		set all_earliest strat_earliest(rename=(&grouping=stratum));
		label earliest="Earliest day target experienced in stratum";
	run;

	proc sort data=earliest; by stratum target; run;
	data lifetest_bm;
		merge lifetest_bm earliest;
		by stratum target;
	run;


/* Merge demographic info into lifetest output */
	proc sort data=lifetest_bm; by usubjid; run;
	proc sort data=dm; by usubjid; run;

	data lifetest_bm_dm ;
		merge lifetest_bm dm;
		by usubjid;
	run;


/* Merge target data into lifetest output with demographic info */
	proc sort data=lifetest_bm_dm ; by usubjid target; run;
	data lifetest_bm_dm_target;
		merge lifetest_bm_dm target_1occur;
		by usubjid target;
		studyday_cat = put(&target_start,8.);
		label survival="Survival Probability"
				studyday_cat="Study Day";
		format survival percent8.2;
		drop domain;
	run;
	
/* Survival Probability Variable	 */
	data survprobs;
		set lifetest_bm_dm_target;
		where censor=0 and survival ne .;
		keep target &target_start censor survival stratum;
		rename survival=survival_new;
	run;
	
	proc sort data=survprobs; by stratum target &target_start censor; run;
	proc sort data=lifetest_bm_dm_target; by stratum target &target_start censor; run;
	
	data sa.&output_data;
		merge survprobs lifetest_bm_dm_target;
		by stratum target &target_start censor;
		survival=survival_new;
		if aestdy ne ".";
		drop survival_new;
	run;

ods select all;

	proc datasets;
		delete ALL_EARLIEST ALL_LIFETEST_DATA ALL_SURVIVALPLOT ALL_TARGET_NUM DM DM_TARG_COMBOS EARLIEST LIFETEST_BM LIFETEST_BM_DM LIFETEST_BM_DM_TARGET LIFETEST_DATA LONG_TARGET_DM NO_OVERALL STRAT_EARLIEST STRAT_LIFETEST_DATA STRAT_SURVIVALPLOT STRATUM_TARGET_NUM SURVPROBS TARGET_1OCCUR TARGET_STRAT_NUM TOTAL_STATS UNIQUE_TARGET;
	run;

/* Stop timer */
data _null_;
  dur = datetime() - &_timer_start;
  put 30*'-' / ' TOTAL DURATION:' dur time13.2 / 30*'-';
run;