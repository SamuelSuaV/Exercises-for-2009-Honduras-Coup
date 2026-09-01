* Estimation 1: Texas model of black male prisoners (per capita) brr

* Housekeeping:
cd "/Users/samuel/Desktop/Economic Impacts of Coup/Exercises-for-2009-Honduras-Coup/Cunningham Excercises/Texas_Prisons/Do"

use ../Data/texas.dta, clear

capture log close
capture log using ./texas.log, replace text

*ssc install synth
*ssc install mat2txt

* Delimit nos deja hacer que el comando dure hasta que haya un ;
#delimit; 
synth 	bmprison 
		bmprison(1990) bmprison(1992) bmprison(1991) bmprison(1988) 
		alcohol(1990) aidscapita
		income ur poverty black(1990) black(1991) black(1992) 
		perc1519(1990)
		,		
		trunit(48) trperiod(1993) unitnames(state) 
		mspeperiod(1985(1)1993) resultsperiod(1985(1)2000)
		keep(../data/synth/synth_bmprate.dta) replace fig;

	   	mat list e(V_matrix);

#delimit cr

graph save Graph ../Figures/synth_tx.gph, replace



/*Explicación:

La primera variable de synth es la explicada. bmprison es la y. Como regresores
se usan algunos años en especifico de la misma variable. Esto permite que el SC
use la variabilidad no explicada por los demás regresores en estos años como una
proxy de las no observadas. trunit nos dice en la variable de unidad del panel 
especificada en tsset, cual es la unidad de tratamiento. trperiod nos dice lo
mismo para el periodo de tiempo. Unitnames nos dice que nombre poner a las
unidades que salen a la derecha de la grafica. mspeperiod nos dice los periodos
donde se crea el fit. resultsperiod nos dice los periodos en la grafica. El keep
guarda los datos con "y treated" y "y synth".


Aprendizajes:
1) Es útil ver para honduras gdp_mean vs gdp_honduras. Los años donde honduras
se desvíe pueden ser usados como regresores como proxy de los no observados.
Esto es como decirle al modelo: Considera que honduras se desvio en t año y por
lo tanto debes darle un peso distinto a los paises que tomen en cuenta ese año.
2) Lo mismo se puede hacer con otros regresores. 
3) La combinación de distintos periodos de la variable a predecir 
4) Dejar una covariable sola (sin el año) hace que se tome un promedio de su
valor en todos los años en el matching discrepancy. 
5) Si los pesos se hacen con las x, esto implica que estamos asumiendo que 
Y es una función lineal de las x. DUDA -> Entonces como se hace con ML?

*/



* Plot the gap in predicted error
use ../data/synth/synth_bmprate.dta, clear
keep _Y_treated _Y_synthetic _time
drop if _time==.
rename _time year
rename _Y_treated  treat
rename _Y_synthetic counterfact
gen gap48=treat-counterfact // Se saca el error (real-estimado)
sort year 
twoway (line gap48 year,lp(solid)lw(vthin)lcolor(black)), yline(0, lpattern(shortdash) lcolor(black)) xline(1993, lpattern(shortdash) lcolor(black)) xtitle("",si(medsmall)) xlabel(#10) ytitle("Gap in black male prisoner prediction error", size(medsmall)) legend(off)
save ../data/synth/synth_bmprate_48.dta, replace

/*
 Ahora calculamos el error de predicción antes y despues del tratamiento.
 Si el error aumenta despues del tratamiento, y es cercano a 0 antes, genera
credibilidad
*/

* Se puede hacer una tabla con los pesos. Se incluyen solo las unidades con peso


* P valores

* Inference 1 placebo test
#delimit;
set more off;
use ../data/texas.dta, replace;




local statelist  1 2 4 5 6 8 9 10 11 12 13 15 16 17 18 20 21 22 23 24 25 26 27 28 29 30 31 32 33 34 35 36 37 38 39 40 41 42 45 46 47 48 49 51 53 55;


foreach i of local statelist {;


synth   bmprison 
        bmprison(1990) bmprison(1992) bmprison(1991) bmprison(1988)
        alcohol(1990) aidscapita(1990) aidscapita(1991) 
        income ur poverty black(1990) black(1991) black(1992) 
        perc1519(1990)
        ,       
            trunit(`i') trperiod(1993) unitnames(state) 
            mspeperiod(1985(1)1993) resultsperiod(1985(1)2000)
            keep(../data/synth/synth_bmprate_`i'.dta) replace;
            matrix state`i' = e(RMSPE); /* check the V matrix*/
            };




 foreach i of local statelist {;
 matrix rownames state`i'=`i';
 matlist state`i', names(rows);
 };




 #delimit cr
local statelist  1 2 4 5 6 8 9 10 11 12 13 15 16 17 18 20 21 22 23 24 25 26 27 28 29 30 31 32 33 34 35 36 37 38 39 40 41 42 45 46 47 48 49 51 53 55


 foreach i of local statelist {
    use ../data/synth/synth_bmprate_`i' ,clear
    keep _Y_treated _Y_synthetic _time
    drop if _time==.
    rename _time year
    rename _Y_treated  treat`i'
    rename _Y_synthetic counterfact`i'
    gen gap`i'=treat`i'-counterfact`i'
    sort year 
    save ../data/synth/synth_gap_bmprate`i', replace
}


use ../data/synth/synth_gap_bmprate48.dta, clear
sort year
save ../data/synth/placebo_bmprate48.dta, replace


foreach i of local statelist {
        
        merge year using ../data/synth/synth_gap_bmprate`i'
        drop _merge
        sort year
        
    save ../data/synth/placebo_bmprate.dta, replace
}




** Inference 2: Estimate the pre- and post-RMSPE and calculate the ratio of the
*  post-pre RMSPE   
set more off
local statelist  1 2 4 5 6 8 9 10 11 12 13 15 16 17 18 20 21 22 23 24 25 26 27 28 29 30 31 32 33 34 35 36 37 38 39 40 41 42 45 46 47 48 49 51 53 55


foreach i of local statelist {
    use ../data/synth/synth_gap_bmprate`i', clear
    
    gen gap3=gap`i'*gap`i'
    egen postmean=mean(gap3) if year>1993
    egen premean=mean(gap3) if year<=1993
    gen rmspe=sqrt(premean) if year<=1993
    replace rmspe=sqrt(postmean) if year>1993
    gen ratio=rmspe/rmspe[_n-1] if year==1994
    gen rmspe_post=sqrt(postmean) if year>1993
    gen rmspe_pre=rmspe[_n-1] if year==1994
    
    mkmat rmspe_pre rmspe_post ratio if year==1994, matrix (state`i')
                                }


* show post/pre-expansion RMSPE ratio for all states, generate histogram
foreach i of local statelist {
    matrix rownames state`i'=`i'
    matlist state`i', names(rows)
                                }


* ssc install mat2txt, replace


    mat state=state1\state2\state4\state5\state6\state8\state9\state10\state11\state12\state13\state15\state16\state17\state18\state20\state21\state22\state23\state24\state25\state26\state27\state28\state29\state30\state31\state32\state33\state34\state35\state36\state37\state38\state39\state40\state41\state42\state45\state46\state47\state48\state49\state51\state53\state55
    mat2txt, matrix(state) saving(../inference/rmspe_bmprate.txt) replace
    insheet using ../inference/rmspe_bmprate.txt, clear
    ren v1 state
    drop v5
    gsort -ratio
    gen rank=_n
    gen p=rank/46
    
    export excel using ../inference/rmspe_bmprate, firstrow(variables) replace


    import excel ../inference/rmspe_bmprate.xlsx, sheet("Sheet1") firstrow clear
    histogram ratio, bin(20) frequency fcolor(gs13) lcolor(black) ylabel(0(2)12) xtitle(Post/pre RMSPE ratio) xlabel(0(1)25)


* Show the post/pre RMSPE ratio for all states, generate the histogram.
list rank p if state==48






* Inference 3: all the placeboes on the same picture
use ../data/synth/placebo_bmprate.dta, replace


* Picture of the full sample, including outlier RSMPE
#delimit;   


twoway (line gap1 year ,lp(solid)lw(vthin))
(line gap2 year ,lp(solid)lw(vthin))
(line gap4 year ,lp(solid)lw(vthin))
(line gap5 year ,lp(solid)lw(vthin))
(line gap6 year ,lp(solid)lw(vthin))
(line gap8 year ,lp(solid)lw(vthin))
(line gap9 year ,lp(solid)lw(vthin))
(line gap10 year ,lp(solid)lw(vthin))
(line gap11 year ,lp(solid)lw(vthin))
(line gap12 year ,lp(solid)lw(vthin))
(line gap13 year ,lp(solid)lw(vthin)) 
(line gap15 year ,lp(solid)lw(vthin)) 
(line gap16 year ,lp(solid)lw(vthin)) 
(line gap17 year ,lp(solid)lw(vthin))
(line gap18 year ,lp(solid)lw(vthin)) 
(line gap20 year ,lp(solid)lw(vthin)) 
(line gap21 year ,lp(solid)lw(vthin)) 
(line gap22 year ,lp(solid)lw(vthin)) 
(line gap23 year ,lp(solid)lw(vthin)) 
(line gap24 year ,lp(solid)lw(vthin)) 
(line gap25 year ,lp(solid)lw(vthin)) 
(line gap26 year ,lp(solid)lw(vthin))
(line gap27 year ,lp(solid)lw(vthin))
(line gap28 year ,lp(solid)lw(vthin)) 
(line gap29 year ,lp(solid)lw(vthin)) 
(line gap30 year ,lp(solid)lw(vthin)) 
(line gap31 year ,lp(solid)lw(vthin)) 
(line gap32 year ,lp(solid)lw(vthin)) 
(line gap33 year ,lp(solid)lw(vthin)) 
(line gap34 year ,lp(solid)lw(vthin))
(line gap35 year ,lp(solid)lw(vthin))
(line gap36 year ,lp(solid)lw(vthin))
(line gap37 year ,lp(solid)lw(vthin)) 
(line gap38 year ,lp(solid)lw(vthin)) 
(line gap39 year ,lp(solid)lw(vthin))
(line gap40 year ,lp(solid)lw(vthin)) 
(line gap41 year ,lp(solid)lw(vthin)) 
(line gap42 year ,lp(solid)lw(vthin)) 
(line gap45 year ,lp(solid)lw(vthin)) 
(line gap46 year ,lp(solid)lw(vthin)) 
(line gap47 year ,lp(solid)lw(vthin))
(line gap49 year ,lp(solid)lw(vthin)) 
(line gap51 year ,lp(solid)lw(vthin)) 
(line gap53 year ,lp(solid)lw(vthin)) 
(line gap55 year ,lp(solid)lw(vthin)) 
(line gap48 year ,lp(solid)lw(thick)lcolor(black)), /*treatment unit, Texas*/
yline(0, lpattern(shortdash) lcolor(black)) xline(1993, lpattern(shortdash) lcolor(black))
xtitle("",si(small)) xlabel(#10) ytitle("Gap in black male prisoners per capita prediction error", size(small))
    legend(off);


#delimit cr


graph save Graph ../Figures/synth_placebo_bmprate.gph, replace


* Drop the outliers (RMSPE is 5 times more than Texas: drops 11, 28, 32, 33, and 41)
* Picture of the full sample, including outlier RSMPE
#delimit;   


twoway (line gap1 year ,lp(solid)lw(vthin))
(line gap2 year ,lp(solid)lw(vthin))
(line gap4 year ,lp(solid)lw(vthin))
(line gap5 year ,lp(solid)lw(vthin))
(line gap6 year ,lp(solid)lw(vthin))
(line gap8 year ,lp(solid)lw(vthin))
(line gap9 year ,lp(solid)lw(vthin))
(line gap10 year ,lp(solid)lw(vthin))
(line gap12 year ,lp(solid)lw(vthin))
(line gap13 year ,lp(solid)lw(vthin)) 
(line gap15 year ,lp(solid)lw(vthin)) 
(line gap16 year ,lp(solid)lw(vthin)) 
(line gap17 year ,lp(solid)lw(vthin))
(line gap18 year ,lp(solid)lw(vthin)) 
(line gap20 year ,lp(solid)lw(vthin)) 
(line gap21 year ,lp(solid)lw(vthin)) 
(line gap22 year ,lp(solid)lw(vthin)) 
(line gap23 year ,lp(solid)lw(vthin)) 
(line gap24 year ,lp(solid)lw(vthin)) 
(line gap25 year ,lp(solid)lw(vthin)) 
(line gap26 year ,lp(solid)lw(vthin))
(line gap27 year ,lp(solid)lw(vthin))
(line gap29 year ,lp(solid)lw(vthin)) 
(line gap30 year ,lp(solid)lw(vthin)) 
(line gap31 year ,lp(solid)lw(vthin)) 
(line gap34 year ,lp(solid)lw(vthin))
(line gap35 year ,lp(solid)lw(vthin))
(line gap36 year ,lp(solid)lw(vthin))
(line gap37 year ,lp(solid)lw(vthin)) 
(line gap38 year ,lp(solid)lw(vthin)) 
(line gap39 year ,lp(solid)lw(vthin))
(line gap40 year ,lp(solid)lw(vthin)) 
(line gap42 year ,lp(solid)lw(vthin)) 
(line gap45 year ,lp(solid)lw(vthin)) 
(line gap46 year ,lp(solid)lw(vthin)) 
(line gap47 year ,lp(solid)lw(vthin))
(line gap49 year ,lp(solid)lw(vthin)) 
(line gap51 year ,lp(solid)lw(vthin)) 
(line gap53 year ,lp(solid)lw(vthin)) 
(line gap55 year ,lp(solid)lw(vthin)) 
(line gap48 year ,lp(solid)lw(thick)lcolor(black)), /*treatment unit, Texas*/
yline(0, lpattern(shortdash) lcolor(black)) xline(1993, lpattern(shortdash) lcolor(black))
xtitle("",si(small)) xlabel(#10) ytitle("Gap in black male prisoners per capita prediction error", size(small))
    legend(off);


#delimit cr


graph save Graph ../Figures/synth_placebo_bmprate2.gph, replace






/* Explicación: 
Corremos synth para cada estado, con peso o no, poniendolo como estado tratado.
Notar que es el mismo modelo exacto. Despues se guardan los errores.

De lo anterior podemos obtener los errores, promediando el error antes del
tratamiento y despues del tratamiento. De aquí sacamos el ranking de estados de
mayor a menor, en post/pre RMSE. El p-valor es el # de estados que pasan texas
sobre el # de estados. Entonces el menor p-valor es 1/J+1 = 46.


Aprendizajes: 
Con todos los países de centro américa no basta para tener signif. estadíst.
El mejor p-valor posible es 1/7 = 0.143.
Para un p-valor de 0.1, se necesitan 10 países.
Para un p-valor de 0.05, se necesitan 20 países. -> America Latina basta
Para un p-valor de 0.01, se necesitan 100 países. -> El sur global tiene 173
*/









/* Dudas:
1) No estaremos capturando el efecto del salario minimo?
Poner minimo como control.
2) Podemos calcular la incertidumbre de los p-valores? Para saber si con 20
países es suficiente para tener un p-valor confiable

