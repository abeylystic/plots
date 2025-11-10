/*Run this portion of code first then followed by the python code for maps*/

options mprint mlogic symbolgen validvarname=v7;

/* Path to Excel file */
%let xls_path = G:/My Drive/Projects papers/Stat Consulting/Map Project/AHA_2021_GA.xlsx;

/*Import trauma centers from the 'GA data' sheet */
libname aha xlsx "&xls_path";

/* Check available sheets/columns */
proc contents data=aha._all_ nods; run;

data work.hosp_raw;
  set aha.'GA data'n;
run;

/* Keep only trauma centers with valid coordinates */
data work.trauma;
  set work.hosp_raw;
  /* Convert lat/longitude safely in case Excel imported them as text */
  lat = input(lat, best32.);
  lon = input(longitude, best32.);
  if not missing(lat) and not missing(lon) and trauml90 > 0;
  length hosp_name $200;
  hosp_name = strip(mname);
  keep hosp_name lat lon trauml90 fcounty;
run;

proc print data=work.trauma(obs=10);
  title "Georgia Trauma Centers with Coordinates";
run;



/* Build Georgia ZIP centroids from SASHELP.ZIPCODE */
proc sql;
  create table work.zip_ga as
  select put(zip, z5.) as zip length=5,
         y as zip_lat,
         x as zip_lon,
         city,
         statecode,
         county
  from sashelp.zipcode
  where statecode='GA';
quit;

/* Rebuild trauma with numeric lat/lon */
data work.trauma;
  set work.hosp_raw;
  lat_num = input(lat, best32.);
  lon_num = input(longitude, best32.);
  if not missing(lat_num) and not missing(lon_num) and trauml90 > 0;
  length hosp_name $200;
  hosp_name = strip(mname);
  keep hosp_name lat_num lon_num trauml90 fcounty;
  rename lat_num = lat  lon_num = lon;   /* now lat/lon are NUMERIC */
run;

/* Verify types */
proc contents data=work.trauma; run;

/* All args to GEODIST are now numeric */
proc sql;
  create table work.zip_trauma_geo as
  select z.zip, z.city, z.county, z.zip_lat, z.zip_lon,
         t.hosp_name, t.lat as hosp_lat, t.lon as hosp_lon,
         geodist(z.zip_lat, z.zip_lon, t.lat, t.lon, 'M') as miles_geo
  from work.zip_ga z, work.trauma t;
quit;

/* OSRM routing (per-pair) with progress tracking (this process can take over 1hr) */
%macro osrm_route(in=work.nearest_geo, out=work.route_results, sleep_sec=0.25, progress_every=25);
  %local nobs i ok fail t0;
  /* fresh output */
  data &out; length zip $5 hosp_name $200 miles_drive 8 time_sec 8 http_code 8; stop; run;
  /* how many rows */
  proc sql noprint;
    select count(*) into :nobs trimmed from &in;
  quit;
  /* counters + start time */
  %let ok=0;
  %let fail=0;
  %let t0=%sysfunc(datetime());
  %do i=1 %to &nobs;
    /* i-th pair; OSRM expects lon,lat */
    data _one;
      set &in (firstobs=&i obs=&i);
      length origin dest url $300;
      origin = cats(put(zip_lon , 15.10), ',', put(zip_lat , 15.10));  /* lon,lat */
      dest   = cats(put(hosp_lon, 15.10), ',', put(hosp_lat, 15.10));
      url    = cats('https://router.project-osrm.org/route/v1/driving/',
                    origin, ';', dest, '?overview=false');
      call symputx('zip'   , zip);
      call symputx('hospnm', hosp_name);
      call symputx('url'   , url);
    run;
    filename resp temp;
    /* Call OSRM; capture HTTP status */
    proc http url="&url" method="GET" out=resp; run;
    %let http_code = &SYS_PROCHTTP_STATUS_CODE;
    %if &http_code = 200 %then %do;
      %let ok=%eval(&ok+1);
      libname jresp json fileref=resp;
      data _pull;
        length zip $5 hosp_name $200;
        set jresp.routes (obs=1);
        zip         = "&zip";
        hosp_name   = "&hospnm";
        miles_drive = distance / 1609.344;   /* meters to miles */
        time_sec    = duration;              /* seconds */
        http_code   = &http_code;
        keep zip hosp_name miles_drive time_sec http_code;
      run;
      libname jresp clear;
    %end;
    %else %do;
      %let fail=%eval(&fail+1);
      data _pull;
        length zip $5 hosp_name $200;
        zip         = "&zip";
        hosp_name   = "&hospnm";
        miles_drive = .; 
        time_sec    = .; 
        http_code   = &http_code;
      run;
    %end;
    proc append base=&out data=_pull force; run;
    filename resp clear;
    /* polite throttle */
    data _null_; call sleep(&sleep_sec, 1); run;
    /* progress to log every PROGRESS_EVERY rows (and on first/last) */
    %if %sysevalf(&i=1 or %sysfunc(mod(&i,&progress_every))=0 or &i=&nobs) %then %do;
      data _null_;
        length msg $200.;
        i   = &i;
        n   = &nobs;
        ok  = &ok;
        fail= &fail;
        t0  = &t0;
        now = datetime();
        pct = 100*i/n;
        elapsed = now - t0;                     /* seconds */
        if elapsed>0 then rate = i/elapsed;     /* rows per sec */
        else rate = .;
        if rate>0 then remain = (n - i)/rate;   /* seconds */
        else remain = .;
        msg = cats('Progress: ', put(i, comma10.), ' / ', put(n, comma10.),
                   ' (', put(pct, 5.1), '%)',
                   ', ok=', put(ok, comma8.), ', fail=', put(fail, comma8.),
                   ', elapsed=', put(elapsed, time8.));
        if remain ne . then msg = cats(msg, ', ETA~', put(remain, time8.), ' remaining');
        putlog msg;
      run;
    %end;
  %end;
%mend;



/* Find Top 5 nearest by straight-line as candidates */
/* (This assumes the "fastest" drive is likely in the top 5 closest) */
proc sort data=work.zip_trauma_geo; 
  by zip miles_geo; 
run;

data work.nearest_top5_geo;
  set work.zip_trauma_geo;
  by zip;
  retain rank;
  if first.zip then rank = 1;
  else rank + 1;
  if rank <= 5; /* Keep the top 5 candidates per ZIP */
  drop rank;
run;

proc print data=work.nearest_top5_geo(obs=15);
  title "Top 5 Straight-Line Candidates (First 3 ZIPs)";
run; title;


/* Another Test on a small sample first */
data work.ng_test_top5;
  set work.nearest_top5_geo;
  if zip in ('30002', '30003', '30004');
run;
%osrm_route(in=work.ng_test_top5, out=work.route_results_test, sleep_sec=0.25, progress_every=5);
proc print data=work.route_results_test; title "OSRM test results (Top 5 Candidates)"; run; title;


/* Full set (~950 ZIPs * 5 candidates = ~4750 pairs) */
/* Adjust sleep_sec as needed for politeness */
%osrm_route(in=work.nearest_top5_geo, out=work.route_results, sleep_sec=0.30, progress_every=25);


/* Format OSRM results */
data work.route_results_fmt;
  set work.route_results;
  length time_text $40;
  time_min = time_sec/60;
  hours = floor(time_min/60);
  mins  = round(mod(time_min,60));
  if hours>0 then time_text = cats(hours,' hour',ifc(hours=1,'','s'),' ',mins,' min');
  else time_text = cats(mins,' min');
  drop hours mins;
run;

/* Join all metrics for all candidates */
proc sql;
  create table work.all_candidate_distances as
  select a.zip, a.city, a.county,
         a.hosp_name, a.hosp_lat, a.hosp_lon,
         a.zip_lat,  a.zip_lon,
         a.miles_geo,                /* Straight-line */
         r.miles_drive,              /* Driving Distance */
         r.time_sec,                 /* Driving Time */
         r.time_text,
         r.http_code
  from work.nearest_top5_geo a
  left join work.route_results_fmt r
    on a.zip = r.zip and a.hosp_name = r.hosp_name
  where r.http_code = 200; /* Only keep successful routes */
quit;


/* Winner by Straight-Line (miles_geo) */
proc sort data=work.all_candidate_distances out=work.winners_geo;
  by zip miles_geo;
run;
data work.winner_geo;
  set work.winners_geo;
  by zip;
  if first.zip;
  length metric_type $20;
  metric_type = 'Straight-Line';
  rename miles_geo = winning_value;
run;

/* Winner by Driving Distance (miles_drive) */
proc sort data=work.all_candidate_distances(where=(not missing(miles_drive))) 
          out=work.winners_drive;
  by zip miles_drive;
run;
data work.winner_drive;
  set work.winners_drive;
  by zip;
  if first.zip;
  length metric_type $20;
  metric_type = 'Driving Distance';
  rename miles_drive = winning_value;
run;

/* Winner by Driving Time (time_sec) */
proc sort data=work.all_candidate_distances(where=(not missing(time_sec))) 
          out=work.winners_time;
  by zip time_sec;
run;
data work.winner_time;
  set work.winners_time;
  by zip;
  if first.zip;
  length metric_type $20;
  metric_type = 'Driving Time';
  rename time_sec = winning_value;
run;

/* Stack all winners into one file */
data work.all_winners_by_zip;
  set work.winner_geo
      work.winner_drive
      work.winner_time;
  /* Keep key columns for the final file */
  keep zip city county metric_type hosp_name winning_value
       miles_geo miles_drive time_sec time_text
       zip_lon zip_lat hosp_lon hosp_lat;
run;

proc sort data=work.all_winners_by_zip;
  by zip metric_type;
run;

/* Print a sample of the new final table */
title "Nearest Trauma Center by 3 Metrics (Sample with Coords)";
proc print data=work.all_winners_by_zip(obs=15) label;
  var zip city metric_type hosp_name zip_lon zip_lat;
run; title;

/* Export the new 'winners' file to CSV */
%let csv_output_path_winners = 'G:/My Drive/Projects papers/Stat Consulting/Map Project/trauma_winners_by_zip.csv';

PROC EXPORT
    DATA=work.all_winners_by_zip
    OUTFILE=&csv_output_path_winners.
    DBMS=CSV
    REPLACE;
RUN;

/* After exporting, import this file in python and create interactive plots */
