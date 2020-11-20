/******************************************************************************/
/* $Id: step1_dataPrep.sas, 1.1 2019/08/01 17:23:48 lafede Exp $*/
/**/
/* Copyright(c) 2019 SAS Institute Inc., Cary, NC, USA. All Rights Reserved.*/
/**/
/* Name: step1_dataPrep.sas */
/**/
/* Purpose: Data preparation for automated survival analysis on clinical trial data. Datasets merged and created data structure needed
				for survival analysis. Code to be deployed in LSAF. */
/**/
/* Author: Laura Federline, Jackie Lanning */
/**/
/* Support: SAS(r) Global Hosting and US Professional Services */
/**/
/* Input: demographic dataset, target dataset */
/**/
/* Output: work.long_target_dm.sas7bdat */
/**/
/* Parameters: Library path to data, name of final output dataset, demographic dataset name, target dataset name, and names for the 6 following variables: 
				unique subject identifier, subject start date, subject end date, event, start day of event, strata */
/**/
/* Dependencies/Assumptions: Input datasets are in sas7bdat format and follow SDTM standards, parameters are correctly
				specified, unique subject identifier variable has the same name in both input datasets */
/**/
/* Usage: SAS 9.4 or later needed */
/**/
/* History:*/
/* ddmmmyyyy userid description (Change Code)*/
/******************************************************************************/

/* Start timer */
%let _timer_start = %sysfunc(datetime());


/* Assign user provided macro variables */
	
	*Input library path containing DM and target datasets;
	%let library_path = "C:\Users\lafede\Documents\Survival Automation\4_13_Final";
	
	*Input desired name of final output data;
	%let output_data = output_4_15;
	
	*Input name of demographic data;
	%let dm_data = dm_fix;
	
	*Input name of sas dataset containing target variable;
	%let target_data = ae_fix;
	
	*Input Unique Subject Identifier variable name;
	%let usubjid = usubjid;
	
	*Input Subject Start Date variable name from demographic dataset;
	%let start = RFSTDTC;
	
	*Input Subject End Date variable name from demographic dataset;
	%let end = RFENDTC;
	
	*Input Target variable name from target dataset;
	%let target = aedecod;
	
	*Input target Start Date variable name from target dataset;
	%let target_start = aestdy;
	
	*Input strata variable name from demographic;
	%let grouping = arm;
	

ods select none;
	
/* Assign library */
	libname SA &library_path;
	

/* Obtain maximum length of Targets */
	proc sql noprint;
		select max(length(&target)) into :target_length from sa.&target_data;
	quit;
	%put &=target_length;
	

/* Manipulating input datasets */

	*Renaming &usubjid to standard name in dm data;
	data dm;
		set sa.&dm_data(rename=(&usubjid=usubjid));
	run;

	*Keeping only first occurence of each target for individual patient,
	renaming &target and &usubjid to standard name in  data,
	set length of target variable;
	proc sort data=sa.&target_data; by &usubjid &target; run;
	data target_1occur;
		length target $&target_length.;
		set sa.&target_data (rename=(&target=target_orig &usubjid=usubjid));
		label &target="target";
		by usubjid target_orig;
		if first.target_orig;
		target=target_orig;
		drop target_orig;
	run;
	
	
/* Get list of unique targets and count */
	proc freq data=target_1occur noprint;
		tables target / out=unique_target(where=(target is not missing) drop=COUNT PERCENT);
	run;	
	
	data _null_;
		if 0 then set unique_target nobs=n;
		call symputx('target_num',n);
	stop;
	run;

/* Creating a tall data structure with (# of subjects)*(# of unique targets) rows */

	*Macro for creating an observation for every subject*target combo;
	%macro tall_target;
		%do i=1 %to &target_num; 
			data _null_;
				set unique_target;
				if _n_=&i then call symputx("target_i",target);
			run;
			data target&i;
				set dm;
				length target $&target_length.;
				target="&target_i";
			run;
		%end;	
	%mend tall_target;
	
	%tall_target;
	
	*Concatenating all datasets created above into one;
	data dm_targ_combos;
		set target1-target&target_num;
	run;	
	
	proc datasets;
		delete target1-target&target_num;
	run;
	
	*Merging target info about patients, creating status var, and adding time for censored obs;
	proc sort data=dm_targ_combos; by usubjid target; run;
	proc sort data=target_1occur; by usubjid target; run;
	data long_target_dm;
		merge dm_targ_combos target_1occur (in=in_target);
		by usubjid target;
		if in_target then status=1;
			else status=0;
		startdate_num = input(&start,yymmdd10.);
		enddate_num = input(&end,yymmdd10.);
		days_study = (enddate_num-startdate_num)+1;
		if status=0 then &target_start=days_study;
	run;

	
ods select all;
		
/* Stop timer */
data _null_;
  dur = datetime() - &_timer_start;
  put 30*'-' / ' TOTAL DURATION:' dur time13.2 / 30*'-';
run;