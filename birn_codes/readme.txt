Yes, sorry about that, I should have put in a brief README of some sort. Here's the procedure:
 
1) get new phantom run, saved as DICOM with separate folders for each scan
 
2) run process.sh: "process.sh <dirname> <name>", e.g. I just ran
 
../../ed_process.sh 301_FE_EPI_200_Dyn_Stab-MRe scan1; ../../ed_process.sh 401_FE_EPI_100_Dyn_Stab-MRe scan2
 
in a new scan directory (ed_process.sh is the version for enhanced DICOM, my actual data is two levels down from the "master" directory, and I put my processed results in directories called "scan1" and "scan2" for the 200 and 100 volume FBIRN protocols, respectively)
 
3) the previous step runs the FBIRN package, and to mine its results (and store them a big master table for each protocol) I use "assemble_xml_data" in MATLAB
 
4) once there is a table, plot_charts in MATLAB will create plots (it will also run html_prep)
 
5) the final product, suitable for web viewing, can then go to a web server, or you can open it in a web browser
 
 
One big gotcha: the code for reading in XML requires a package called the XML Toolbox. It's available on MathWorks, but last I checked it hasn't been updated in a long, long time, with the result that it is no longer fully compatible with recent MATLAB versions. If it was released as source it might have been possible to tweak it to update the problematic call or calls, but it was released as P-code. I've just been running it in R2012b to avoid the issue.  
 
I expect you can get through step 2 if you've installed the FBIRN package and the stuff it relies on (bxh_xcede). I don't expect steps 3 and on will work for you because there will no doubt be dependencies on in house MATLAB things, and you'll have to decide whether you want to just see what they do (or ignore them) and do your own thing, or address those dependencies by getting stuff. I'm not sure exactly what those bits are going to be that it depends on, but I'm happy to share them if you're interested -- it may be an iterative process, in that case, because copying each thing that's missing might introduce additional dependencies…