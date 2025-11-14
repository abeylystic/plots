/* Topic: Analyzing Upsets in Men's Professional Tennis: The Impact of Surface, Match Format,
   and Tournament Round (ATP Tour 2025) */
   
/* Research Question 1 (RQ1): Do upset rates vary by playing surface?
   Research Question 2 (RQ2): What factors are associated with an increased probability of an upset? */

/* ENV + OUTPUT */
options validvarname=any nocenter nodate nonumber;  /* allow 'Best of'n names */
ods noproctitle; 
ods graphics on / width=6in height=4in border=off;

%let men_xlsx = G:/My Drive/Augusta University files/Fall 2025/DATS 7510/DATS7510/Project/Men_2025.xlsx;
%let rtfpath  = G:/My Drive/Augusta University files/Fall 2025/DATS 7510/DATS7510/Project/ATP2025_Men_Report_10292025.rtf;

ods rtf file="&rtfpath" style=HTMLBlue bodytitle startpage=no;

title "Analyzing Upsets in Men's Professional Tennis: The Impact of Surface, Match Format, and Tournament Round (ATP Tour 2025)";


/* DATA IMPORT */
ods text="^{style [font_weight=bold font_size=11pt] 1) Import ATP 2025 (Men) from Excel}";
proc import datafile="&men_xlsx" dbms=xlsx out=men_raw replace;
  getnames=yes;
run;


/* DATA CLEANING */
%let LEN_TOURN  = 100;
%let LEN_PLAYER =  50;
%let LEN_LOC    =  50;
%let LEN_SER    =  40;
%let LEN_ROUND  =  20;
%let LEN_COURT  =  12;
%let LEN_SURF   =  10;
%let LEN_COMM   =  40;
%let LEN_TOURID =  20;

ods text="^{style [font_weight=bold font_size=11pt] 2) Clean & harmonize Men data (types, enums, labels)}";
data men_clean(label="ATP 2025 � Men (cleaned)");
  /* Character variables */
  length gender $6 tournament $&LEN_TOURN winner $&LEN_PLAYER loser $&LEN_PLAYER
         location $&LEN_LOC series_or_tier $&LEN_SER round_clean $&LEN_ROUND
         court_clean $&LEN_COURT surface_clean $&LEN_SURF comment_clean $&LEN_COMM
         tour_id $&LEN_TOURID status_flag $4;
  /* Numeric variables */
  length wrank_n lrank_n wpts_n lpts_n b365w_n b365l_n best_of
         wsets_n lsets_n w1 l1 w2 l2 w3 l3 w4 l4 w5 l5
         straight_sets match_date 8;

  set men_raw;

  /* Tag & ids */
  gender  = "Men";
  tour_id = strip(ATP);

  /* Numeric conversions */
  if vtype(WRank)='N' then wrank_n = WRank;   else wrank_n = input(strip(vvalue(WRank)), ?? best32.);
  if vtype(LRank)='N' then lrank_n = LRank;   else lrank_n = input(strip(vvalue(LRank)), ?? best32.);
  if vtype(WPts) ='N' then wpts_n  = WPts;    else wpts_n  = input(strip(vvalue(WPts )), ?? best32.);
  if vtype(LPts) ='N' then lpts_n  = LPts;    else lpts_n  = input(strip(vvalue(LPts )), ?? best32.);
  if vtype(B365W)='N' then b365w_n = B365W;   else b365w_n = input(strip(vvalue(B365W)), ?? best32.);
  if vtype(B365L)='N' then b365l_n = B365L;   else b365l_n = input(strip(vvalue(B365L)), ?? best32.);

  /* Best-of: default to 3 if missing */
  best_of = .;
  if vtype('Best of'n)='N' then best_of = 'Best of'n;
  else best_of = input(strip(vvalue('Best of'n)), ?? best32.);
  if missing(best_of) then best_of = 3;

	/* Date: numeric or character (quiet parse when char) */
	format match_date yymmdd10.;
	if vtype(Date)='N' then match_date = Date;
	else match_date = input(strip(vvalue(Date)), ?? anydtdte.);
	
  /* Per-set games + sets won */
  w1=W1; l1=L1; w2=W2; l2=L2; w3=W3; l3=L3; w4=W4; l4=L4; w5=W5; l5=L5;
  wsets_n = Wsets;  
  lsets_n = Lsets;

  /* Text normalization */
  surface_clean  = substr(lowcase(strip(coalescec(Surface, ""))), 1, &LEN_SURF);
  court_clean    = substr(lowcase(strip(coalescec(Court,   ""))), 1, &LEN_COURT);
  round_clean    = substr(          strip(coalescec(Round,  "")), 1, &LEN_ROUND);
  series_or_tier = substr(          strip(coalescec(Series, "")), 1, &LEN_SER);
  tournament     = substr(          strip(Tournament),            1, &LEN_TOURN);
  winner         = substr(          strip(Winner),                1, &LEN_PLAYER);
  loser          = substr(          strip(Loser),                 1, &LEN_PLAYER);
  location       = substr(          strip(Location),              1, &LEN_LOC);

  /* Status flag - keep only completed matches*/
  comment_clean = substr(lowcase(strip(coalescec(Comment,"completed"))), 1, &LEN_COMM);
  if index(comment_clean,'walkover')>0 or index(comment_clean,'ret')>0 
    then status_flag='DROP';
  else status_flag='KEEP';

  /* Single debug line if any row gives errors */
  if _error_ then do;
    putlog 'NOTE: Bad parse on row=' _n_
           ' WRank=' WRank= ' LRank=' LRank= ' WPts=' WPts= ' LPts=' LPts=
           ' B365W=' B365W= ' B365L=' B365L= ' Best of=' 'Best of'n= ' Date=' Date=;
    _error_ = 0;
  end;

  /* Labels */
  label
    gender         = "Tour Gender"
    tour_id        = "Tournament ID (ATP code)"
    location       = "Tournament Location"
    tournament     = "Tournament Name"
    match_date     = "Date of Match"
    series_or_tier = "Series (ATP)"
    court_clean    = "Court Type (Indoor/Outdoor)"
    surface_clean  = "Surface (Clay/Hard/Grass/Carpet)"
    round_clean    = "Round of Match"
    best_of        = "Maximum Sets Playable"
    winner         = "Match Winner"
    loser          = "Match Loser"
    wrank_n        = "Winner's Rank at Tournament Start"
    lrank_n        = "Loser's Rank at Tournament Start"
    wpts_n         = "Winner's Ranking Points at Tournament Start"
    lpts_n         = "Loser's Ranking Points at Tournament Start"
    w1             = "Winner Games in Set 1"
    l1             = "Loser Games in Set 1"
    w2             = "Winner Games in Set 2"
    l2             = "Loser Games in Set 2"
    w3             = "Winner Games in Set 3"
    l3             = "Loser Games in Set 3"
    w4             = "Winner Games in Set 4"
    l4             = "Loser Games in Set 4"
    w5             = "Winner Games in Set 5"
    l5             = "Loser Games in Set 5"
    wsets_n        = "Sets Won by Winner"
    lsets_n        = "Sets Won by Loser"
    comment_clean  = "Match Comment (Completed/Walkover/Ret.)"
    b365w_n        = "Bet365 Odds � Winner"
    b365l_n        = "Bet365 Odds � Loser"
    status_flag    = "Completion Status Flag";

  /* Keep only the analysis vars */
  keep gender tour_id location tournament match_date series_or_tier
       court_clean surface_clean round_clean best_of
       winner loser wrank_n lrank_n wpts_n lpts_n
       w1 l1 w2 l2 w3 l3 w4 l4 w5 l5
       wsets_n lsets_n comment_clean status_flag
       b365w_n b365l_n;
run;

/* Keep completed matches only */
data atp25_men;
  set men_clean;
  if status_flag='KEEP';
run;


/* DESCRIPTIVE ANALYSIS */
ods text="^{style [font_weight=bold font_size=11pt] 3) Descriptive summaries for ATP 2025 (Men)}";

/* Table 1: Match Distribution by Surface */
title "Table 1: Match Distribution by Surface";
proc freq data=atp25_men; 
  tables surface_clean / nocum; 
run;

/* Table 2: Match Distribution by Tournament Round */
title "Table 2: Match Distribution by Tournament Round";
proc freq data=atp25_men; 
  tables round_clean; 
run;

/* Table 3: Player Rankings and Points Summary */
title "Table 3: Player Rankings and Points Summary";
proc means data=atp25_men n nmiss mean std min p25 median p75 max maxdec=1;
  var wrank_n lrank_n wpts_n lpts_n;
run;


/* RESEARCH QUESTION 1 */
/* RQ1: Do upset rates vary by playing surface? */
ods text="^{style [font_weight=bold font_size=12pt] RQ1: Do upset rates vary by surface (Men only)?}";

/* Define upset (winner's entry rank number > loser's, both >0) */
data rq_base;
  set atp25_men;
  if nmiss(wrank_n,lrank_n)=0 and wrank_n>0 and lrank_n>0 then upset = (wrank_n > lrank_n);
    else upset = .;
  label upset="Upset (1=Winner had worse rank)";
run;

/* Remove rows without a definable upset */
data rq1_use; 
  set rq_base; 
  if upset in (0,1); 
run;

/* Calculate upset rates by surface */
proc sql;
  create table rq1_surface as
  select surface_clean as surface,
         mean(upset*1.0) as upset_rate format=percent8.1,
         sum(upset=1) as n_upsets,
         count(*) as n_matches
  from rq1_use
  group by surface_clean;
quit;

/* Table 4: Upset Rate by Surface */
title "Table 4: Upset Rate by Surface";
proc print data=rq1_surface noobs label; 
  label surface="Surface Type" upset_rate="Upset Rate" n_upsets="Number of Upsets" n_matches="Number of Matches";
run;

/* Table 5: Chi-square test for surface differences */
title "Table 5: Chi-square Test for Surface Differences in Upset Rates";
proc freq data=rq1_use;
  tables surface_clean*upset / chisq norow nocol;
  label surface_clean="Surface Type" upset="Upset Occurred";
run;


/* RESEARCH QUESTION 2 */
/* RQ2: What factors are associated with an increased probability of an upset? */
ods text="^{style [font_weight=bold font_size=12pt] RQ2: Factors associated with upsets}";

/* Create a rank-gap covariate (positive if winner had worse rank) */
data rq2_use;
  set rq1_use;
  rank_gap = wrank_n - lrank_n;   /* >0 means winner ranked worse */
  label rank_gap = "Winner Rank - Loser Rank (positive=worse winner rank)";
run;

/* Simplify round categories for modeling */
data rq2_model;
  set rq2_use;
  if round_clean in ("1st Round","2nd Round","3rd Round","4th Round") then round_cat = "Early Round";
  else if round_clean in ("Quarterfinals","Semifinals") then round_cat = "Quarter/Semi Finals";
  else if round_clean = "The Final" then round_cat = "Final";
  else round_cat = "Other";
  label round_cat = "Tournament Round Category";
run;


/* Table 6: Upset Summary by Tournament Round Category */
title "Table 6: Upset Summary by Tournament Round Category";
proc sql;
  create table roundcat_summary as
  select round_cat,
         count(*) as n_matches,
         sum(upset=1) as n_upsets,
         mean(upset*1.0) as upset_rate format=percent8.1
  from rq2_model
  where round_cat ne ''
  group by round_cat;
quit;

proc print data=roundcat_summary noobs label;
  label round_cat="Tournament Round Category"
        n_matches="Number of Matches"
        n_upsets="Number of Upsets"
        upset_rate="Upset Rate";
run;

/* Table 7: Logistic Regression - Upset Probability by Round */
title "Table 7: Logistic Regression - Upset Probability by Round";
proc logistic data=rq2_model;
  class round_cat(ref='Final') / param=ref;
  model upset(event='1') = round_cat;
  label upset = "Upset Occurred";
run;

/* Calculate predicted probabilities by round */
proc means data=rq2_model noprint;
  class round_cat;
  var upset;
  output out=round_upsets mean=upset_rate n=n_matches;
run;

/* Export Figure 1 as PNG */
ods listing gpath="G:/My Drive/Augusta University files/Fall 2025/DATS 7510/DATS7510/Project/";
ods graphics / reset imagename="upset_prob" imagefmt=png width=6in height=4in;

/* Figure 1: Upset Probability by Tournament Round */
title "Figure 1: Upset Probability by Tournament Round";
proc sgplot data=round_upsets;
  where round_cat ne '';
  vbar round_cat / response=upset_rate datalabel categoryorder=respdesc
                   fillattrs=(color=steelblue) datalabelattrs=(size=10);
  yaxis label="Upset Rate" values=(0 to 0.5 by 0.1);
  xaxis label="Tournament Round";
run;

ods listing close;

/* Table 7: Logistic Regression - Upset Probability by Match Format */
title "Table 7: Logistic Regression - Upset Probability by Match Format";
proc logistic data=rq2_model;
  class best_of(ref='5') / param=ref;
  model upset(event='1') = best_of;
  label best_of = "Match Format (Best of)" upset = "Upset Occurred";
run;

/* Calculate predicted probabilities by match format */
proc means data=rq2_model noprint;
  class best_of;
  var upset;
  output out=format_upsets mean=upset_rate n=n_matches;
run;


/* Table 8: Upset Summary by Match Format */
title "Table 8: Upset Summary by Match Format";
proc sql;
  create table matchformat_summary as
  select best_of as Match_Format,
         count(*) as n_matches,
         sum(upset=1) as n_upsets,
         mean(upset*1.0) as upset_rate format=percent8.1
  from rq2_model
  where best_of in (3,5)
  group by best_of;
quit;

proc print data=matchformat_summary noobs label;
  label Match_Format="Match Format (Best of)"
        n_matches="Number of Matches"
        n_upsets="Number of Upsets"
        upset_rate="Upset Rate";
run;


/* Export Figure 2 as PNG */
ods listing gpath="G:/My Drive/Augusta University files/Fall 2025/DATS 7510/DATS7510/Project/";
ods graphics / reset imagename="match_form" imagefmt=png width=6in height=4in;

/* Figure 2: Upset Probability by Match Format */
title "Figure 2: Upset Probability by Match Format";
proc sgplot data=format_upsets;
  where best_of in (3,5);
  vbar best_of / response=upset_rate datalabel
                 fillattrs=(color=darkgreen) datalabelattrs=(size=10);
  yaxis label="Upset Rate" values=(0 to 0.5 by 0.1);
  xaxis label="Match Format (Best of)" integer;
run;

ods listing close;

/* SAVE FINAL DATASET */
ods text="^{style [font_weight=bold font_size=11pt] Save analysis-ready dataset}";
data work.atp2025_men_clean;
  set atp25_men;
run;

/* Close RTF output */
ods rtf close;
title;
