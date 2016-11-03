#!/usr/bin/perl
#---------------------------
# 降水確率を取得する
# 2009/06/21 created
# param config/send_list filepath
#---------------------------
use warnings;
use strict;

use LWP::Simple;
use Encode qw/from_to/;

#---------
# 送信リスト
#---------
my $sl_path = shift;
open(SL,"<$sl_path") || die "sendList file open error.\n";
my @sendList = ();
while (my $line = <SL>) {
	chomp($line);
	my @ary = split(/\|/,$line);
	my $ref = {
		flg	=>	$ary[0],
		address	=>	$ary[1],
		carrier	=>	$ary[2],
		prob	=>	$ary[3],
		url	=>	$ary[4],
		city	=>	$ary[5],
	};
	push(@sendList,$ref);
}
close(SL);

=pod
for(my $i=0;$i<=$#sendList;$i++){
	print "----------------\n";
	print $sendList[$i]->{'flg'},"\n";
	print $sendList[$i]->{'address'},"\n";
	print $sendList[$i]->{'carrier'},"\n";
	print $sendList[$i]->{'prob'},"\n";
	print $sendList[$i]->{'url'},"\n";
	print "----------------\n";
	print "\n";
}
=cut


#---------
# 設定
#---------
# タグ設定
my $tagStart     = '<wm:forecast term="week"';	# 週間天気 開始タグ
my $tagEnd       = '</wm:forecast>';		# 週間天気 終了タグ

my $tagStartDay  = '<wm:content date="';	# 日別天気 開始タグ
my $tagEndDay    = '</wm:content>';		# 日別天気 終了タグ

my $tagStartProb = '<wm:prob hour="';		# 降水確率 開始タグ
my $tagEndProb   = '</wm:prob>';		# 降水確率 終了タグ

my $tagStartCont = '<wm:weather>';		# 天気予報 開始タグ
my $tagEndCont   = '</wm:weather>';		# 天気予報 終了タグ

my $tagStartTemp = '<wm:temperature unit="℃">';# 気温 開始タグ
my $tagEndTemp   = '</wm:temperature>';		# 気温 終了タグ

my $tagStartMax  = '<wm:max>';			# 最高気温 開始タグ
my $tagEndMax    = '</wm:max>';			# 最高気温 終了タグ

my $tagStartMin  = '<wm:min>';			# 最低気温 開始タグ
my $tagEndMin    = '</wm:min>';			# 最低気温 終了タグ


#---------
# 処理
#---------
my $logDate = &getCurDate();
print $logDate,"\n";

for(my $i=0;$i<=$#sendList;$i++){

	# sendListの送信フラグが1の場合は処理を行う
	if($sendList[$i]->{'flg'} eq '1'){
		print "getWeather [$sendList[$i]->{'address'}][$sendList[$i]->{'city'}]\n";

		# 今日の日付
		my $curDate = &getCurDate();
	
		# 指定日の降水確率を取得
		my $prob = &getProb($curDate,$sendList[$i]->{'url'});
		
		# どれかの降水確率が規定値を超えていた場合、メール送信
		if(
			$prob->{'prob1'} ge $sendList[$i]->{'prob'} ||
			$prob->{'prob2'} ge $sendList[$i]->{'prob'} ||
			$prob->{'prob3'} ge $sendList[$i]->{'prob'} ||
			$prob->{'prob4'} ge $sendList[$i]->{'prob'}
		){
			# メール送信
			&sendMail($prob,$sendList[$i]->{'address'},$sendList[$i]->{'carrier'},$sendList[$i]->{'city'});
		}
	}
}
exit;

# 今日の日付
sub getCurDate{
	my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time);
	$year += 1900;
	$mon += 1;

	return "$year/$mon/$mday";
}

# 指定日の降水確率を取得
sub getProb{
	my $date = shift;
	my $url = shift;

	# 天気予報RSSを取得する
	my $res = get($url);

	# RSSから週間天気部分を取得
	my $weekStr = substr($res,index($res,$tagStart));
	$weekStr = substr($weekStr,0,index($weekStr,$tagEnd)+length($tagEnd));

	# 週間天気部分から今日の日付を取得
	my $todayStr = substr($weekStr,index($weekStr,$tagStartDay.$date));
	$todayStr = substr($todayStr,0,index($todayStr,$tagEndDay));

	# 時間別降水確率を取得
	my $prob1 = getProbByHour("00-06",$todayStr);
	my $prob2 = getProbByHour("06-12",$todayStr);
	my $prob3 = getProbByHour("12-18",$todayStr);
	my $prob4 = getProbByHour("18-24",$todayStr);

	# 天気予報を取得
	my $cont = substr($todayStr,index($todayStr,$tagStartCont)+length($tagStartCont));
	$cont = substr($cont,0,index($cont,$tagEndCont));

	# 気温を取得
	my $temp = substr($todayStr,index($todayStr,$tagStartTemp)+length($tagStartTemp));
	$temp = substr($temp,0,index($cont,$tagEndTemp));

	# 最高気温
	my $max = substr($temp,index($temp,$tagStartMax)+length($tagStartMax));
	$max = substr($max,0,index($max,$tagEndMax));

	# 最高気温
	my $min = substr($temp,index($temp,$tagStartMin)+length($tagStartMin));
	$min = substr($min,0,index($min,$tagEndMin));

	my $rtn = {
		prob1 => $prob1,
		prob2 => $prob2,
		prob3 => $prob3,
		prob4 => $prob4,
		cont  => $cont,
		max   => $max,
		min   => $min,
	};

	return $rtn;
}

# 時間別降水確率を取得
sub getProbByHour{
	my $hour = shift;
	my $str = shift;

	my $start = $tagStartProb . $hour;

	$str = substr($str,index($str,$start));
	$str = substr($str,0,index($str,$tagEndProb)+length($tagEndProb));

	my $prob = $str;
	$prob =~ s/<.*?>//g; 

	if($prob !~ m/[0-100]/){
		$prob = "-";
	}

	return $prob;

}

# メール送信
sub sendMail{
	my $prob = shift;
	my $sendTo = shift;
	my $carrier = shift;
	my $city = shift;

	my $sendmail = '/usr/sbin/sendmail';
	my $from = 'AMEAME_kerota2009@sakura.ne.jp';
	my $to = $sendTo;
	my $subject = "$city";

	my $content  = "[$city]\n";
	   $content .= "$prob->{'cont'}\n";
	   $content .= "-----\n";
	   $content .= "00-06 : $prob->{'prob1'} %\n";
	   $content .= "06-12 : $prob->{'prob2'} %\n";
	   $content .= "12-18 : $prob->{'prob3'} %\n";
	   $content .= "18-24 : $prob->{'prob4'} %\n";
	   $content .= "-----\n";
	   $content .= "High : $prob->{'max'} C\n";
	   $content .= "Low  : $prob->{'min'} C\n";

my $msg = <<"_TEXT_";
$content
_TEXT_

	# sendmail コマンド起動
	open(SDML,"| $sendmail -t -i") || die 'sendmail error';
	# メールヘッダ出力
	print SDML "From: $from\n";
	print SDML "To: $to\n";

	# メール件名出力
	#from_to($subject,'euc-jp','utf8');
	print SDML "Subject: $subject\n";

	print SDML "Content-Type: text/plain;charset=UTF-8\n";
	print SDML "Content-Transfer-Encoding: 7bit\n\n";

	# メール本文出力
	#from_to($msg,'euc-jp','utf8');
	print SDML "$msg";

	# sendmail コマンド閉じる
	close(SDML); 

}

exit;
