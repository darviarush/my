<?php
Yii::import('CActiveForm');

class MyCActiveForm extends CActiveForm {
	
	public function autoCompliteField($model, $attribute, $config = array(), $htmlOptionsNumber = array())
	{	
		echo $this->textField($model, $attribute."_id", array_replace_recursive(array('readonly'=>1, 'size'=>4), $htmlOptionsNumber));
		$rel = $model->$attribute;
		#if(!isset($rel)) eval("\$rel = new ".ucfirst($attribute)."();");
		$this->widget('zii.widgets.jui.CJuiAutoComplete', array_replace_recursive(array(
			'model'	 => $rel,
			'attribute' => 'name',
			'source' => Yii::app()->createUrl($attribute.'/autocomplete'),	// может быть js-функцией
			'options' => array(
				'delay'=>300,
				//'minLength'=>'2',
				'showAnim'=>'fold',
				// обработчик события, выбор пункта из списка
				'select' =>'js: function(event, ui) {
					this.value = ui.item.label;
					$("#'.CHtml::activeId($model, $attribute.'_id').'").val(ui.item.id);	// устанавливаем значения скрытого поля
					return false;
				}',
			),
			#htmlOptions => $htmlOptions
		), $config));
		
		?>
			<select style="width:20px" onclick='$("#<?php echo CHtml::activeId($model->$attribute, 'name') ?>").autocomplete("search", "")'></select>
		<?php
	}
}
