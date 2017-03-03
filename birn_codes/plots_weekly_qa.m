% plotting QA data

data = load('WeeklyQA.txt'); % WeeklyQA.txt is 7 column array. 
dn = datenum(data(:,3),data(:,1),data(:,2));
figure()

for i=1:4
     if i==1
        subplot(4,1,1)
        plot(dn,data(:,4),'.')
        %datetick('x',12,'keepticks','keeplimits')
        datetick('x',12)

        title('Percent Flutuation')
        ylabel('%')
       
     elseif i==2
        subplot(4,1,2)
        plot(dn,data(:,5),'.')
        %datetick('x',12,'keepticks','keeplimits')
        datetick('x',12)

        title('Drift(within run)')
        ylabel('%')
       
     elseif i==3
        subplot(4,1,3)
        plot(dn,data(:,6),'.')
        %datetick('x',12,'keepticks','keeplimits')
        datetick('x',12)

        title('Signal to Noise Ratio (SNR)')
        ylabel('a.u')        
        
     elseif i==4
        subplot(4,1,4)
        plot(dn,data(:,7),'.')
        %datetick('x',12,'keepticks','keeplimits')
        datetick('x',12)

        title('Signal to Fluctuation Noise Ratio (SFNR)')
        xlabel('Date(mmmyy)')
        ylabel('a.u')
     end
end
     