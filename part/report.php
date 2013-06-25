<?php
/* @var $this SiteController */
/* @var $model ContactForm */
/* @var $form CActiveForm */

$this->pageTitle=Yii::app()->name . ' - '.$model->name;
$this->breadcrumbs=array(
	'Отчёты' => array("site/report"),
	$model? $model->name: "Нет отчётов",
);

?>

<style>
.legend table { width: auto }
.menuis .active { background-color: MistyRose; border: solid 1px Salmon; }
.menuis .noactive, .menuis .active { float: left; margin-right: 10px; padding: 2px }
</style>


<?php if($model): ?>

<h1><?php echo $model->name ?></h1>

<div class="menuis">
<?php
$type = isset($_REQUEST["type"])? $_REQUEST["type"]: $model->type;
$filter = $_REQUEST["Filter"];
foreach(array("tab"=>"Таблица", "square"=>"Квадратный отчёт", "chart"=>"Круговая диаграмма", "flot"=>"График") as $a=>$b) {
	$param = array('site/report', 'id'=>$model->id);
	$param["type"] = $a;
	$src = "&type=$a";
	echo "<div class=".($type==$a? "active": "noactive").">".CHtml::link($b, $param, array("onclick"=>"js:location = String(location).replace(/&type=\w+|$/, '$src'); return false"))."</div>";
}

?>
</div>


<p>

<a id=preview-show href="#" onclick="$('#filter-form,#preview-hide').show(); $(this).hide(); return false" <?php if($qbe->is_filter) echo 'style="display:none"'; ?>>Показать фильтры</a>
<a id=preview-hide href="#" onclick="$('#filter-form,#preview-hide').hide(); $('#preview-show').show(); return false" <?php if(!$qbe->is_filter) echo 'style="display:none"'; ?>>Скрыть фильтры</a>

</p>

<div id=filter-form class="search-form" <?php if(!$qbe->is_filter) echo 'style="display:none"'; ?>>
<div class="wide form">

<?php $form=$this->beginWidget('CActiveForm', array(
	'action'=>Yii::app()->createUrl($this->route),
	'method'=>'get',
));


foreach($qbe->columnSlice() as $slice) {

	$fname = $slice[0];
	$label = isset($slice[2])? $slice[2]: $fname;
	$name = "Filter[$fname]";
	$id = "Filter_$fname";
?>

	<div class="row">
		<?php echo CHtml::label($label, $id); ?>
		<?php $this->widget('zii.widgets.jui.CJuiAutoComplete', array(
			"id"=>$id,
			'name' => $name,
			'value' => $filter[$fname],
			'source' => Yii::app()->createUrl('site/qbeautofield', array("id"=>$model->id, "col"=>$fname)),	// может быть js-функцией
			'options' => array(
				'delay'=>300,
				//'minLength'=>'2',
				'showAnim'=>'fold',
				'open' => 'js: function(event, ui) {
					var x = $(this)
					
					setTimeout(function() {
						var ul = x.data("autocomplete").menu.activeMenu
						ul.find("li").each(function() { 
							var item = $(this).data("ui-autocomplete-item")
							var val = $("<sup />").text(item.value+" ")
							$(this).find("a").html(item.label).prepend(val)
						})
					}, 0)
				}'
				/*'select' =>'js: function(event, ui) {
					this.value = ui.item.value
					return false
				}',*/
			),
			'htmlOptions' => array("size"=>70)
			));
		?>
	</div>

<?php
}
$count = $_REQUEST["count"];
if($type == "chart") {
	echo CHtml::label("Количество обрабатываемых строк (0 - все)", "count");
	echo CHtml::textField("count", isset($count)? $count: 30);
} else if(isset($count)) {
	echo CHtml::hiddenField("count", $count);
}

if(isset($type)) echo CHtml::hiddenField("type", $type);

echo CHtml::hiddenField("id", $model->id);
?>

	<div class="row buttons">
		<?php echo CHtml::submitButton('Искать', array("name" => "", "onclick" => "js:for(var i=0, n=yw0.elements.length; i<n; i++) { var e=yw0.elements[i]; if(e.value.replace(/^\s+/, '')=='') e.name = '' }")); ?>
	</div>

<?php $this->endWidget() ?>

</div><!-- search-form -->
</div>

<?php if($type == 'tab'): ?>

<?php

$this->widget('zii.widgets.grid.CGridView', array(
	'hideHeader'=>0,
	'dataProvider'=>$qbe->dataProvider(),
	'columns'=>$qbe->columnNames(),
	'enableHistory'=>true
));

echo $qbe->errorHTML();

?>

<?php elseif($type == 'square'): ?>

<?php

$data = $qbe->squareData();

$this->widget('zii.widgets.grid.CGridView', array(
	'id'=>"square-table",
	'hideHeader'=>1,
	'columns'=>$qbe->squareColumns($data),
	'dataProvider'=>new CArrayDataProvider($data, array(
		'pagination' => array(
			'pageSize' => count($data),
		))),
));

//$this->widget('application.extensions.EFixedHeaderTable.EFixedHeaderTableWidget', array("id"=>"square-table"));

echo $qbe->errorHTML();
// <a href="#" onclick="$('#square-table table.items').fixedHeaderTable('destroy'); return false">Зафиксировать</a>
?>




<?php elseif($type == 'chart'): ?>


<?php

$this->widget('application.extensions.EFlot.EFlotGraphWidget', array(
	'data'=> $qbe->chartData(),
	'options'=> array(
		'series' => array(
			'pie' => array('show' => true, 'label'=>array('show'=>false,
				'formatter'=> "js:formatLabel"
			)), // 'background'=>array('opacity'=>0.5, 'color'=> '#000'))),
		),
		'grid'=>array('hoverable'=>true, 'clickable'=>true),
		'legend' => array('show' => true, "labelFormatter"=> "js:formatLabel")
	),
	'htmlOptions'=>array('style'=>'width:100%; height: 600px'),
));
echo $qbe->errorHTML();

?>

<script>

function newCount() {
	var val = count.value
	if(!/^\d+$/.test(val)) $("#error").text(val+" - Не число")
	else location = String(location).replace(/&count=\d+|$/, '&count='+val)
}

function formatLabel(lab, series) {
	var i, s = ""
	for(i in series) s += i + " "

	return Math.round(series.percent*100)/100 + "% " + lab
}

$("#interactive").bind("plothover", function(event, pos, item) {
	//item.series.label
})
//$("#interactive").bind("plotclick", pieClick);
</script>


<?php elseif($_REQUEST['type'] == 'flot'): ?>

<?php
$this->widget('application.extensions.EFlot.EFlotGraphWidget', array(
	'data'=> $qbe->flotData(),
	'options'=> array(),
	'htmlOptions'=>array('style'=>'width:100%;height:600px;'),
));
echo $qbe->errorHTML();
?>

<?php else: ?>

Не выбран режим представления.

<?php endif ?>

<?php else: ?>

Нет отчётов.

<?php endif ?>