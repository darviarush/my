<?php
/* @var $this SiteController */

$this->pageTitle=Yii::app()->name . ' - Конструктор отчётов';
$this->breadcrumbs=array(
	'Отчёты'=>array('site/report', 'id'=>$model->id),
	'Конструктор отчётов',
	$model->name
);

Yii::app()->getClientScript()->registerCoreScript('jquery.ui');
Yii::app()->getClientScript()->registerCssFile(Yii::app()->getClientScript()->getCoreScriptUrl().'/jui/css/base/jquery-ui.css');
Yii::import('ext.qtip.QTip');

QTip::qtip("#not_found");

?>
<script type='text/javascript' src="js/jquery.json-2.4.js"></script>

<style><!--
.items td { cursor: pointer }
.base td {vertical-align: top}
.operators div {display: inline; cursor: pointer}

div.odd {background: #E5F1F4; }
div.even {background: #F8F8F8; }
div.odd:hover, div.even:hover {background: #ECFBD4;}
div.odd div, div.even div {display: inline; cursor: pointer;}

.const {border: 1px solid grey}
.const_date {border: 1px solid green}
.const_datetime {border: 1px solid blue}

.Fn { color: royalblue }

.key {color:green}

#report-menu {position: absolute !important; width: 400px;}
#error, .error {background: LightCoral}
--></style>

<h1>Конструктор отчётов</h1>

Захватите мышкой поле и перетащите:

<?php
$css = Yii::app()->getAssetManager()->publish(Yii::getPathOfAlias('zii.widgets.assets')).'/gridview/styles.css';
Yii::app()->getClientScript()->registerCssFile($css);
?>

<div class=grid-view>
<table id=columns class=items>
<thead>
<tr><?php foreach($tables as $table=>$columns) { 
	if($table[0]!=".") echo isset($tables[".$table"])? "<th colspan=2>$table": "<th>$table";
} ?>
</thead>
<tbody>
<?php for($i=0; $i<$count; $i++): ?><tr class=<?php echo $i % 2==0? 'odd': 'even'; ?>>
<?php foreach($tables as $table=>$columns): if($table[0]==".") $table = substr($table, 1); 
echo '<td><div type="column" name="'.CHtml::encode("$table.{$columns[$i][0]}").'">';
echo CHtml::encode($columns[$i][0]) ?><sup class="key"><?php echo CHtml::encode($columns[$i][1]) ?></sup></div>
<?php endforeach ?>
<?php endfor ?>
</tbody>
</table>
</div>

<h3>
<span id=report-id><?php echo $model->id ?></span>
<span id=report-name onclick="show_field.call(this)"><?php echo CHtml::encode($model->name); ?></span>
</h3>



<div id=operators class=operators>
<?php
$operators = array("and"=>"<font color=green>И</font>", "or"=>"<font color=red>Или</font>", "not"=>"Не",
"="=>"=", "<>"=>"≠", "<"=>"&lt;", ">"=>"&gt;", "<="=>"≤", ">="=>"≥",
"+"=>"<font color=red>+</font>", "-"=>"-", "*"=>"*", "/"=>"/",
"("=>"(", ")"=>")",
"is null"=>"Пусто", "is not null"=>"Не пусто",
"like"=>"≈", "in"=> "В",
"DISTINCT" => "<font color=red>Отличные</font>",
":sum"=>"Сумма", ":count"=>"Количество", ":avg"=>"Среднее арифметическое",
":Fn"=>"Fn",
".constant" => "<div class='const' onclick='show_field.call(this)'>Константа</div>",
".as" => "<font color=red>:</font><div class='const' onclick='show_field.call(this)'>Название</div>",
".user" => "<b>Пользователь</b><div class='const' onclick='show_field.call(this)'>1</div>",
//".constant_date" => "<div class='const_date' onclick='show_field_date.call(this, \"date\")'>Дата</div>",
//".constant_datetime" => "<div class='const_datetime' onclick='show_field_time.call(this)'>Время</div>"
);
foreach($operators as $op=>$html) {
	echo '<div type="'.($op[0]=='.'? 'const': 'op').'" name="'.CHtml::encode($op).'"'.($op[0]==":"? " class=Fn onclick='show_field_fn.call(this)'": "").'>'.$html."</div>\n";
}
?>
</div>

<div style="height:32px">
	<img id=preloader src="images/save.png">
</div>

<div id=error></div>

<?php echo "<a href='".CHtml::encode(Yii::app()->createUrl('site/report', array('id'=>$model->id)))."'>Посмотреть</a>"; ?>

<label for="report-for_users">Видимый для пользователей</label>
<input id=report-for_users type=checkbox <?php echo $model->for_users? 'checked': '' ?> onclick="save.call(this)">


<table class="base">
<tr>
<?php
$sortable = array(
"qbe-select" => "Выбрать",
"qbe-where" => "Фильтр",
"qbe-group" => "Группировка",
"qbe-having" => "Фильтр",
"qbe-order" => "Сортировка"
);
foreach($sortable as $id=>$name): ?>
<td>
<h5><?php echo CHtml::encode($name) ?></h5>
<?php echo "<div id='$id'></div>"; ?>
<?php endforeach ?>
<script>
var Sortable = <?php echo CJavaScript::encode($sortable) ?>;
var Operators = <?php echo CJavaScript::encode($operators) ?>
</script>

<td>

<div id=qbe-erase class=odd_even><img src='images/corzina.png'></div><br>Выбросить

</table>


<a id=preview-show href="#" onclick="$('#preview-sql,#preview-hide').show(); $(this).hide(); return false">Показать sql</a>
<a id=preview-hide href="#" onclick="$('#preview-sql,#preview-hide').hide(); $('#preview-show').show(); return false" style="display:none">Скрыть sql</a>
<div id=preview-sql style="display:none"><?php echo CHtml::encode($model->sql) ?></div>


<div id=report-type>Тип отчёта по умолчанию: <?php
$report_type = array("tab"=>"Таблица", "square"=>"Квадратный", "chart"=>"Круговая диаграмма", "flot"=>"График");
foreach($report_type as $type=>$name) echo "<input type=radio name=report_type value=$type onchange='save()'".($model->type == $type? " checked": "")."> ".CHtml::encode($name);
?></div>

<div class=grid-view>
<table id=square class=items>
<tr><th><th>Квадратный отчёт<th>Квадратный отчёт. Итоги<th>Круговая диаграмма<th>График<th>Автодополнение

<tr><th>x
<td id=report-square-x onclick='show_field.call(this)' title="Ячейки верхней строки таблицы. По умолчанию - 1-й столбец. Должно начинаться со столбца (без $) по которому будет происходить объединение. Для суммирования столбца нужно добавлять :sum, для подсчёта - :count. Например: id $name">
<td id=report-square-cut onclick='show_field.call(this)' title="Ячейка верхнего левого угла таблицы. Формат - html. Может содержать столбцы. Для суммирования столбца нужно добавлять :sum, для подсчёта - :count. Например: $id:count \ $sum:sum">
<td id=report-chart-x onclick='show_field.call(this)' title="Столбец, по которому будет строится круговая диаграмма. Должен быть числовым. По умолчанию - 1-й. Диаграмма сама вычислит процент. Например: count">
<td id=report-flot-x onclick='show_field.call(this)' title="Стобцы для значений по оси X. Если столбцов несколько, то на графике будет несколько линий. По умолчанию берутся все столбцы, кроме первого. Например: count sum">
<td id=report-autocomplete onclick='show_field.call(this)' title="Формат строки выпадающего списка автодополнения в фильтре соответствующего столбца. По умолчанию - соответствующий столбец. Формат - html. Например: &amp;lt;sup&amp;gt;$count &amp;lt;sup&amp;gt;$name&amp;lt;/sup&amp;gt;&amp;lt;/sup&amp;gt;">
<tr><th>y
<td id=report-square-y onclick='show_field.call(this)' title="Ячейки левого крайнего столбца таблицы. По умолчанию - 2-й столбец. Можно сделать из него несколько: $a:sum&amp;lt;td&amp;gt;$b:sum&amp;lt;td&amp;gt;$c:count. Должно начинаться со столбца (без $) по которому будет происходить объединение. Для суммирования столбца нужно добавлять :sum, для подсчёта - :count. Например: now $now&amp;lt;td&amp;gt;$count:sum&amp;lt;td&amp;gt;$sum:sum">
<td id=report-square-iy onclick='show_field.call(this)' title="Ячейка левого нижнего угла таблицы. Для суммирования столбца нужно добавлять :sum, для подсчёта - :count. Например: Итого&amp;lt;td&amp;gt;$count:sum&amp;lt;td&amp;gt;$sum:sum">
<td id=report-chart-y onclick='show_field.call(this)' title="Метка значения в круговой диаграмме. По умолчанию - 2-й столбец. Формат - html. Например: $name &amp;lt;img src=$src&amp;gt;">
<td id=report-flot-y onclick='show_field.call(this)' title="Столбец для оси Y. Может быть как числовым, так и датой. По умолчанию - 1-й. Например: now">
<td title="Не используется">

<tr><th>cell
<td id=report-square-cell onclick='show_field.call(this)'  title="Отображение в ячейке. По умолчанию - 3-й столбец. Формат: html. Например: $count">
<td id=report-square-icell onclick='show_field.call(this)' title="Ячейки нижней строки таблицы. Для суммирования столбца нужно добавлять :sum, для подсчёта - :count. Например: $count:sum">
<td title="Не используется">
<td title="Не используется">
<td title="Не используется">

</table>
</div>




<script>
function show_field() {
	var offset = $(this).offset()
	var width = $(this).width()
	$("<input style='position:absolute' onkeydown='escape_field.call(this, event)' onblur='hide_field.call(this)' />")
		.css("left", offset.left)
		.css('top', offset.top)
		.width(width<100? 100: width)
		.appendTo('body')
		.val($(this).text())
		.prop('constant_field', this)
		.focus()
}

function hide_field() {
	var fld = $(this).prop('constant_field')
	$(fld).text($(this).val())
	var fn = $(fld).prop('hide_fn')
	if(fn) fn.call(fld, this)
	$(this).remove()
	save()
}

function show_field_fn() {
	this.hide_fn = function() { $(this).attr('name', ":" + $(this).text()) }
	show_field.call(this)
}

function escape_field(e) {
	if((e.charCode || e.which) == 27) $(this).attr("onblur", "").remove()
	else if((e.charCode || e.which) == 13) hide_field.call(this)
}

var save_cancel = true
var save_counter = 0
function save() {
	if(save_cancel) return;
	var json = {}

	$(".odd_even:not(#qbe-erase)").each(function() {
		var rows = []
		$(this).find("> div").each(function() {
			var row = []
			$(this).find("> div").each(function() {
				var x = $(this)
				var type = x.attr("type")
				var name = x.attr("name")
				if(type) {
					var val = {type: type, name: name}
					if(type == "const") val['val'] = x.find('> div').text()
					row.push(val)
				}
			})
			if(row.length) rows.push(row)
		})
		if(rows.length) json[this.id] = rows
	})

	var name = $("#report-name").text()
	var id = $("#report-id").text()
	var for_users = $("#report-for_users").attr("checked")? 1: 0
	var type = $("#report-type input[type=radio]:checked").val()
	json['square'] = {
		square_x: $("#report-square-x").text(),
		square_y: $("#report-square-y").text(),
		square_cell: $("#report-square-cell").text(),
		square_cut: $("#report-square-cut").text(),
		square_iy: $("#report-square-iy").text(),
		square_icell: $("#report-square-icell").text(),
		chart_x: $("#report-chart-x").text(),
		chart_y: $("#report-chart-y").text(),
		flot_x: $("#report-flot-x").text(),
		flot_y: $("#report-flot-y").text(),
		autocomplete: $("#report-autocomplete").text()
	}
	json = $.toJSON(json)

	$("#preloader").attr("src", "images/saving.gif")
	save_counter++
	var caller = ''//arguments.callee.caller
	console.log('saving='+save_counter+' '+caller)
	$.ajax({
		url: <?php echo CJavaScript::encode(Yii::app()->createUrl('site/reportqbesave')) ?>,
		data: {content: json, name: name, id: id, for_users: for_users, type: type, explain: $("#preview-sql").css('display') != 'none'? 1: -1 },
		error: function(XMLHttpRequest, textStatus, errorThrown) {
			$("#preloader").attr("src", "images/error.png")
			$("#error").html('ошибка '+textStatus+" "+errorThrown+' '+XMLHttpRequest.responseText)
			save_counter--
			console.log('error='+save_counter+' '+caller)
		},
		success: function(data, textStatus) {
			if(--save_counter == 0) {
				var j
				if(data[0]=='{') j = $.parseJSON(data)
				if(j && !j.errors) {
					$("#preview-sql").text(j.sql)
					$("#error").html('')
					$("#preloader").attr("src", "images/saved.png")
					create_explain(j.explain)
				}
				else {
					if(j) {
						var ul = $("<ul></ul>")
						for(var err in j.errors) ul.append($("<li></li>").text(" "+j.errors[err]).prepend($("<b></b>").text(err)))
						$("#error").html("").append(ul)
					} else $("#error").html(data)
					$("#preloader").attr("src", "images/error.png")
				}
			}
			console.log('success='+save_counter+' '+caller+' '+data)
			//$("#report-id").text(data)
			//alert('сохранён '+data)
		}
	})
}

function create_explain(explain) {
	if(!explain) return;
	if(!(explain instanceof Array)) {
		var div = $("<div class=error></div>").text(explain.msg).prepend($("<b></b>").text(explain.code+": "))
		$("#preview-sql").append("<p />").append(div)
		return;
	}
	if(explain.length == 0) return;
	
	var table = $("<table class=items></table>")
	var row = $("<tr></tr>").appendTo(table)
	for(var k in explain[0]) row.append($("<th></th>").text(k))
	for(var i=0; i<explain.length; i++) {
		row = $("<tr></tr>").appendTo(table).addClass(i % 2 == 0? 'odd': 'even')
		var u = explain[i]
		for(k in u) {
			row.append($('<td></td>').text(u[k]))
		}
	}
	var div = $("<div class=grid-view />").append(table)
	$("#preview-sql").append("<br>").append(div)
}

function erase_receive(event, ui) {
	$(this).find("div").remove()
}

function odd_even() {
	var self = this.id? $(this): $(this).parent()
	if(this.id) $(this).sortable({
		connectWith: '.odd_even',
		update: odd_even
	})
	.addClass('odd_even')
	var prev_empty
	self.find("> div").each(function() {
		prev_empty = $(this).children().length == 1
	})
	if(!prev_empty) odd_even.new_row().appendTo(self)
	self.find("> div").each(function(idx) { this.className = idx%2? "even": "odd" })
	save()
}

function odd_even_receive(event, ui) {
	$(this).find("> div[type=column]").each(function() {
		if($(this).prop("received")) return;
		var name = $(this).attr("name")
		$(this).html(odd_even.column(name))
		$(this).prop("received", 1)
	})
}

$.extend(odd_even, {
	template: "<div class=odd><img src='images/and_icon.png'>&nbsp;</div>",
	conf_ex: {
		items: '> div',
		connectWith: '#qbe-erase,.odd,.even',
		receive: odd_even_receive,
		update: odd_even
		//remove: sort_remove
	},
	new_row: function() { return $(odd_even.template).sortable(odd_even.conf_ex) },
	column: function(name) {
		var column = name.replace(/^[^\.]+\./, "")
		var table = name.replace(/\..*/, "")
		return " <sup>"+table+"</sup>"+column+" "
	}
})



$(function() {
//	var ex = $("#ex > div").sortable(conf_ex)
	
	$("#columns td > div, #operators > div").draggable({
		cursor:'move',
		revert:'invalid',
		helper:'clone',
		connectToSortable:'.odd,.even'
	})
	
	$("#qbe-erase").sortable({
		items: '> div',
		receive: erase_receive
	})
	
	var content = <?php echo CJavaScript::encode($content) ?>;

	var square = content['square']
	if(square) {
		delete content['square']
		for(var k in square) {
			var m = square[k]
			$("#report-"+k.replace(/_/, '-')).text(m)
		}
	}

	for(var i in content) {
		var x = $("#"+i)
		var rows = content[i]
		for(var j=0; j < rows.length; j++) {
			var row = rows[j]
			var r = odd_even.new_row()
			x.append( r )
			for(var k=0; k < row.length; k++) {
				var attr = row[k]
				var name = attr.name
				var type = attr.type
				var html
				var div = $("<div />").attr("type", type).attr('name', name)
				if(type == 'op') {
					if(name[0] == ":") { 
						html = name in Operators? Operators[name]: name.slice(1)
						div.addClass('Fn').attr('onclick', 'show_field_fn.call(this)')
					}
					else if(name in Operators) html = Operators[name]
					else throw "Неизвестный оператор: "+name
				}
				else if(type == 'column') html = odd_even.column(name)
				else if(type == 'const') {
					html = $("<div />").html(' '+Operators[name]+' ')
					html.find("div").text(attr['val'])
					html = html.html()
				}
				else html = "type="+type+" name="+name
				r.append( div.html(html) ).prepend(' ').append(' ')
			}
		}
	}
	
	for(var i in Sortable) odd_even.call($("#"+i)[0])
	save_cancel = false
	
	create_explain(<?php if($model->explainas) echo CJavaScript::encode(json_decode($model->explainas, true)) ?>)
	
	
	$("#square td").qtip({
		content: {
			text: false // Use each elements title attribute
		},
		//content: 'bottomLeft',
		position: {
			corner: {
				tooltip: 'bottomLeft', // Use the corner...
				target: 'topRight' // ...and opposite corner
			}
		},
		style: {
			tip: true,
			name: 'red'
		}
   })
	//alert(JSON.stringify(Sortable))
	//alert($.toJSON(Sortable))
})
</script>