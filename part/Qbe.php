<?php

function mem1() {
	return system("ps --no-headers --format size -p ".getmypid())+0;
}

function mem($s = "") {
	global $BUF_DEBUG;
	$arr = debug_backtrace(DEBUG_BACKTRACE_PROVIDE_OBJECT, 2);
	#print_r($arr);
	$fn = $arr[1]["function"];
	if($s!=="") {
		if(is_string($s)) $s .= " ";
		else $s = print_r($s, true);
	}
	$BUF_DEBUG[] = "mem $s$fn()=".number_format(memory_get_usage(), 0, ".", " ")."\n";
}


function trace() {
	header("Content-Type: text/plain");
	foreach(debug_backtrace() as $a) echo "{$a[file]}:{$a[line]} ".$a["class"].$a["type"].$a["function"]."(".array_map(function($x) {return print_r($x, true); }, $a["args"]).")\n";
	exit;
}

function show() {
	global $BUF_DEBUG;
	header("Content-Type: text/plain; charset=utf-8");
	foreach($BUF_DEBUG as $s) echo $s;
	exit;
}


class MyFilter {
	public $attributes;

	function __construct($attributes) {
		print_r($attributes);
		$this->attributes = $attributes;
	}

	function __get($attribute) {
		return $this->attributes[$attribute];
	}
	
	function getValidators($attribute) {
		return array();
	}
	
	function hasErrors() {
		return false;
	}

}

class Qbe {
	
	public $tables, $select, $from, $table, $join, $where, $group, $having, $order, $sql, $content, $column, $column_having, $user_id, $error, $is_filter;
	private $_notab;
	static $S = null;
	static $limit_auto_complete = 15;
	static $group_func = array(":sum"=>"Сумма", ":count"=>"Количество", ":avg"=>"Среднее", ":min"=>"Min", ":max"=>"Max", ":std"=>"STD", ":stddev"=>"STDDEV", ":bit_or"=>"bit or", ":bit_and"=>'bit_and', ":group_concat"=>'Объединить');
	static $filter_op = array('='=>1, '<'=>1, '>'=>1, "<="=>1, ">="=>1);
	static $rel = null;	// таблицы в ключях должны быть упорядочены в алфавитном порядке: table2.table1, если table2 < table1
	
	function __construct($content, $user_id = null) {
	
		$arr = json_decode($content, true);
		$this->content = $arr;
		$this->user_id = $user_id;
		
		$this->loadSchema();

		$this->select = $this->join_qbe($arr['qbe-select'], ", ", "as");
		$this->where  = $this->join_qbe($arr['qbe-where']);
		$this->group  = $this->join_qbe($arr['qbe-group'], ", ");
		$this->having = $this->join_qbe($arr['qbe-having']);
		$this->order  = $this->join_qbe($arr['qbe-order'], ", ");

		$this->join();

		$this->sql = $this->get_sql();
	}

	function get_schema() {
		$cs = Yii::app()->db->connectionString;
		preg_match('/\bdbname=(\w+)/', $cs, $arr);
		return $arr[1];
	}

	function loadSchema() {
		if(self::$rel) return;
		$sql = "SELECT table_name, column_name, referenced_table_name, referenced_column_name
		FROM information_schema.KEY_COLUMN_USAGE
		WHERE TABLE_SCHEMA = :schema AND POSITION_IN_UNIQUE_CONSTRAINT=1";
		$cmd = Yii::app()->db->createCommand($sql);
		$cmd->bindParam(":schema", self::get_schema(), PDO::PARAM_STR);
		$info = $cmd->queryAll();
		foreach($info as $row) {
			$tab = $row['table_name'];
			$ref_tab = $row['referenced_table_name'];
			if($tab < $ref_tab) $rel["$tab.$ref_tab"] = array($row["column_name"], $row["referenced_column_name"]);
			else $rel["$ref_tab.$tab"] = array($row["referenced_column_name"], $row["column_name"]);
		}
		self::$rel = $rel;
	}

	function split_filter_op(&$value) {
		$op = self::$filter_op;
		$op1 = substr($value, 0, 1);
		$op2 = substr($value, 0, 2);
		if($op[$op2]) { $op_ = $op2; $value = substr($value, 2); }
		else if($op[$op1]) { $op_ = $op1; $value = substr($value, 1); }
		else $op_ = "like";
		$value = trim($value);
		return $op_;
	}

	function set_filters($filters) {
		if(!$filters) return;

		foreach($filters as $name=>$value) {
			if(trim($value) == "") continue;

			$hav = $this->column_having[$name];
			$name = $hav[1];

			$name = self::col_quote($name);
			$op_ = $this->split_filter_op($value);
			$cond = "$name $op_ ".self::quote($value);

			if($hav[0]) $having[] = $cond;
			else $where []= $cond;
		}

		if(!$where and !$having) return;

		$this->is_filter = 1;

		if($where) {
			if($this->where) array_unshift($where, "({$this->where})");
			$this->where = join(" AND ", $where);
		}
		else {
			if($this->having) array_unshift($having, "({$this->having})");
			$this->having = join(" AND ", $having);
		}

	}

	function get_sql($without = array(), $diff = false) {

		if($diff) $without = array_diff_assoc(array("select", "from", "where", "group", "having", "order"), $without);

		if(!in_array("select", $without)) $select = "SELECT {$this->select}";
		if(!in_array("from", $without) && $this->from) $from = " FROM {$this->from}";
		if(!in_array("where", $without) && $this->where) $where = " WHERE {$this->where}";
		if(!in_array("group", $without) && $this->group) $group = " GROUP BY {$this->group}";
		if(!in_array("having", $without) && $this->having) $having = " HAVING {$this->having}";
		if(!in_array("order", $without) && $this->order) $order = " ORDER BY {$this->order}";

		return "$select$from$where$group$having$order";
	}

	function join_qbe($rows, $sep = "", $as = "") {
		if(!$rows) return "";
		$db = Yii::app()->db;
		foreach($rows as $key=>$row) {
			if($key != 0) {
				if($sep) $sql .= $sep;
				else {
					$div1 = $rows[$key+1][0];
					$div2 = $rows[$key-1][-1];
					if(!(
						$div1['type'] == "op" and ($div1['name'] == 'and' or $div1['name'] == 'or') or
						$div2['type'] == "op" and ($div2['name'] == 'and' or $div2['name'] == 'or')
					))
						$sql .= " AND ";
				}
			}
			$exp = $this->expression($row);
			if($as) {
				$this->column[] = $name = $this->col_name($row, ++$k, $exp, $having);
				$a = explode(":", $name);
				$this->column_having[$a[0]] = $having;
			}
			$sql .= $exp;
		}
		return $sql;
	}

	function col_quote($val) {
		return "`".preg_replace('/([\\`])/', '\\$1', $val)."`";
	}

	function quote($val) {
		return "'".preg_replace('/([\\\'])/', '\\$1', $val)."'";
	}

	function expressions($rows = null) {
		if($rows === null) $rows = $this->content['qbe-select'];
		foreach($rows as $row) {
			$exp = $this->expression($row);
			$this->col_name($row, ++$k, $exp, $having);
			$expressions[] = $exp;
		}
		return $expressions;
	}

	function col_name($row, $k, &$exp, &$having) {
		$last = $row[count($row)-1];
		if($last["type"]=='const' and $last['name']=='.as') {
			if(count($row) == 2 and $row[0]['type']=='column') {
				list($tab, $col) = explode(".", $row[0]['name']);
				$having = array(0, $col, $exp);
			} else {
				$a = explode(":", $last['val']);
				$having = array(1, $a[0], $exp);
			}
			return $last['val'];
		}
		if(count($row) == 1 and $last['type']=='column') {
			list($tab, $col) = explode(".", $last['name']);
			$having = array(0, $col, $exp);
			return $col;
		}

		$name = "name$k";
		$exp .= " AS $name";
		$having = array(1, $name, $exp);
		return $name;
	}

	function expression($row) {
		foreach($row as $div) {
			$type = $div['type'];
			$name = $div['name'];
			$val = $div['val'];

			if($type == 'const') {
				if($name == '.as') { $a = explode(":", $val); $s = "AS ".self::col_quote($a[0]); }
				else if($name == '.user')		$s = self::quote($this->user_id? $this->user_id: $val);
				else $s = self::quote($val);

				if($prev['type'] == 'op' && $prev['name'][0] == ':')	$sql .= "($s)";
				else $sql .= " $s";
			} else if($type == 'column') {
				list($table, $column) = explode(".", $name);
				$this->tables[$table] = 1;
				if($prev['type'] == 'op' && $prev['name'][0] == ":")		$sql .= "($name)";
				else 					$sql .= " ".$name;
			} else if($name == "(" && $prev['type'] == 'op' && $prev['name'][0] == ":") {
				$sql .= "(";
			} else if($name[0] == ":") {
				$sql .= " ".substr($name, 1);
			} else $sql .= " ".$name;
			$prev = $div;
		}

		return $sql;
	}

	function check_group_operation($rows) {
		foreach($rows as $row) {
			foreach($row as $div) {
				$type = $div['type'];
				$name = $div['name'];
				$val = $div['val'];
				if($type == 'op' && isset(self::$group_func[$name])) return true;
			}
		}
		return false;
	}

	function autocomplete($col, $term) {

		$mask = $this->content["square"]["autocomplete"];

		preg_match_all('/\$(\w+)/', $mask, $cols);
		$cols = $cols[1];
		array_unshift($cols, $col);

		$qbe_select = $this->content["qbe-select"];
		$columnAs = $this->columnAs();
		foreach($cols as $column) {
			if(isset($is_col[$column])) continue;
			$is_col[$column] = 1;
			$k = array_search($column, $columnAs);
			$rows[] = $qbe_select[$k];
		}

		$exp = $this->expressions($rows);
		$this->split_filter_op($term);
		$term = self::quote($term."%");

		if( $this->check_group_operation($rows) ) {
			$column = self::col_quote($col);
			$having = " HAVING $column like $term";
		} else {
			$nexp = preg_replace('/as\s+`\w+`$/i', '', $exp[0]);
			$where = " WHERE $nexp like $term";
		}

		#if($this->group) $group = " GROUP BY ".$this->group;
		$group = " GROUP BY 1";

		$exp = implode(", ", $exp);

		$sql = "SELECT $exp FROM ".$this->from."$where$group$having limit ".self::$limit_auto_complete;
		#echo "$sql `$mask`";
		try {
			$all = Yii::app()->db->createCommand($sql)->queryAll();
		} catch(Exception $e) {
			$all = array();
			$res = array();
			$this->error = $e->getMessage();
		}

		$mask = self::cell_tpl($mask);

		foreach($all as $row) $res[] = array(label=>$mask($row), value=>$row[$col]);

		return $res;
	}

	function join() {
		$tables = array_keys($this->tables);
		$len = count($tables);
		if(!$tables) {}
		else if($len == 1) $this->from = $this->table = $tables[0];
		else {
			sort($tables);
			if(!self::$S) self::alg();
			$this->table = $tables[0];
			$bilo[$tables[0]] = 1;
			for($i=1; $i<$len; $i++) {
				$from = $tables[$i-1];
				$to = $tables[$i];
				
				if($bilo[$to]) continue;
				
				$j = self::create_join($from, $to);
				if($j) {
					$bilo[$to] = 1;
					$join .= $j;
				} else {
					$arr = self::$S["$from.$to"];
					if($arr[0] != $from) $arr = array_reverse($arr);
					for($k=1; $k < count($arr); $k++) {
						$from1 = $arr[$k-1];
						$to1 = $arr[$k];
						if($bilo[$to1]) continue;
						$join .= self::create_join($from1, $to1);
						$bilo[$to1] = 1;
					}
				}
			}
			$this->join = $join;
			$this->from = $this->table.' '.$this->join; //.' '.json_encode(self::$S);
		}
	}
	
	function create_join($from, $to) {
		$path = self::get_path($from, $to);
		$rel = self::$rel[$path];
		if(!$rel) return false;
		if($from > $to) $rel = array_reverse($rel);
		return " INNER JOIN `$to` ON `$from`.`{$rel[0]}` = `$to`.`{$rel[1]}`";
	}
	
	function get_path($tab1, $tab2) {
		$path = array($tab1, $tab2);
		sort($path);
		return $path[0].".".$path[1];
	}
	
	function alg() {
		foreach(self::$rel as $rel=>$ids) {
			list($tab1, $tab2) = explode(".", $rel);
			$tables[$tab1] = 1;
			$tables[$tab2] = 1;
			$V[$tab1][$tab2] = 1;
			$V[$tab2][$tab1] = 1;
		}
		
		foreach($tables as $tab1=>$null) 
		foreach($tables as $tab2=>$null) {
			if($tab1 == $tab2 || $V[$tab1][$tab2]) continue;
			$A = array(array($tab1));
			$out = null;
			while($A) {
				$new = array();
				foreach($A as $R) {
					$a = $R[count($R)-1];
					foreach($V[$a] as $tab=>$null) {
						if($tab == $tab2) { $R[] = $tab; $out = $R; break(3); }
						if(in_array($tab, $R)) continue;
						$row = $R;
						$row[] = $tab;
						$new[] = $row;
					}
				}
				$A = $new;
			}
			if($out) $S[self::get_path($tab1, $tab2)] = $out;
		}
		self::$S = $S;
	}

	function get_count_sql() {
		$sql = $this->get_sql(array("select", "order"));
		if($this->group || $this->having) {
			foreach($this->column_having as $name=>$a) if(preg_match('/\b'.$name.'\b/', $this->group." ".$this->having)) $cols[] = $a[2];
			$cols = implode(", ", $cols);
			if(!$cols) $cols = 1;
			$count_sql = "SELECT $cols $sql";
			$count_sql = "SELECT count(*) FROM ($count_sql) AS ___A___";
		} else if(!$this->from) {
			$count_sql = "SELECT 1";
		} else {
			$count_sql = "SELECT count(*) $sql";
		}
		return $count_sql;
	}

	function errorHTML() {
		return $this->error? "<div class=error style='background: LightCoral'>{$this->error}</div>": "";
	}

	function columnNames() {
		return $this->column;
	}

	function columnSlice() {
		foreach($this->column as $col) $slice[] =  explode(":", $col);
		return $slice;
	}

	function columnAs() {
		foreach($this->columnSlice() as $slice) $as[] = $slice[0];
		return $as;
	}

	function columnSet() {
		foreach($this->columnSlice() as $k=>$slice) { $slice[3] = $k; $set[$slice[0]] = $slice; }
		return $set;
	}

	function get_sort() {
		foreach($this->column as $key=>$col) {
			$i = $key + 1;
			$a = explode(":", $col);
			$sort[$a[0]] = array(
				'asc'=>"$i",
				'desc'=>"$i DESC"
			);
		}
		return $sort;
	}

	function dataProvider($pageSize = 20) {
		try {
			$count = Yii::app()->db->createCommand($this->get_count_sql())->queryScalar();
			$opt = array(
				'totalItemCount'=>$count,
				'sort'=>array(
					'attributes'=> $this->get_sort(),
					'defaultOrder'=> $this->order
				),
			);

			if($pageSize) $opt['pagination']=array('pageSize'=>$pageSize);

			return new CSqlDataProvider($this->get_sql(array("order")), $opt);

		} catch(Exception $e) {
			$this->error = $e->getMessage();
			return new CArrayDataProvider(array());
		}
	}


	function data() {

		try {
			$data = Yii::app()->db->createCommand($this->get_sql())->queryAll();
		} catch(Exception $e) {
			$this->error = $e->getMessage();
			$data = array();
		}
		return $data;
	}
	
	function squareColumns($data) {
		$column = $data[0];

		$col = array();
		foreach($column as $k=>$x) $col[] = array('name'=>"A$k", 'type'=>'raw', 'value'=>"\$data[$k]");
		return $col;
	}

	function cell_tpl($x) {
		$x = str_replace('"', '\"', $x);
		$x = preg_replace('/\$(\w+)(?::\w+)?/', '".CHtml::encode(\$row["$1"])."', $x);
		$x = create_function('$row', "return \"$x\";");
		return $x;
	}

	function group_tpl($x) {
		if(!preg_match_all('/\$(\w+)(?::(\w+))?/', $x, $arr)) return function() {};
		$col = $arr[1];
		$g = $arr[2];
		
		foreach($col as $k=>$c) {
			if($g[$k] == 'sum') $sum[] = $c;
			else if($g[$k] == 'count') $count[] = $c;
			else $column[] = $c;
		}
		
		$fn = function($row, &$with) use ($sum, $count, $column) {
			foreach($sum as $c) $with[$c] += $row[$c];
			foreach($count as $c) $with[$c]++;
			foreach($column as $c) $with[$c] = $row[$c];
		};
		
		return $fn;
	}
	
	function squareData() {
		$order = $this->order;
		$this->order = '';
		$rows = $this->data();
		$this->order = $order;

		$column = $this->columnAs();
		$square = $this->content["square"];
		
		$Head = $square["square_x"];		// заголовок
		$Left = $square["square_y"];		// столбец слева, могут быть групповые операции. Подсчёт по ячейкам справа
		$Cell = $square["square_cell"];		// ячейки внутри
		
		$LeftHead = $square["square_cut"];	// верхний левый угол, могут быть групповые операции. Подсчёт по ячейкам справа
		$LeftFoot = $square["square_iy"];	// ячейка внизу слева, могут быть групповые операции. Подсчёт по ячейкам справа
		$Foot = $square["square_icell"];	// ячейки внизу, могут быть групповые операции. Подсчёт по ячейкам сверху
		
		if( preg_match('/^\w+ /', $Head) ) list($group_head, $Head) = explode(' ', $Head, 2);
		else { $group_head = $column[0]; $Head = "\$".$column[0]; }
		if( preg_match('/^\w+ /', $Left) ) list($group_left, $Left) = explode(' ', $Left, 2);
		else { $group_left = $column[1]; $Left = "\$".$column[1]; }
				
		$gLeftHead = self::group_tpl($LeftHead);
		$gLeft = self::group_tpl($Left);
		$gFoot = self::group_tpl($Foot);
		$gLeftFoot = self::group_tpl($LeftFoot);
		
		$square = array(&$Left, &$Head, &$Cell, &$Foot, &$LeftHead, &$LeftFoot);
		
		foreach($square as $k=>&$x) {
			if(!trim($x)) { $col = $column[$k]; $x = '$'.($col? $col: $column[0]); }
			$x = self::cell_tpl($x);
		}

		foreach($rows as $row) {
			$h = $row[$group_head];
			$l = $row[$group_left];
		
			if(isset($left[$l])) $l = $left[$l]; else $l = $left[$l] = count($left)+1;
			if(isset($head[$h])) $h = $head[$h]; else $h = $head[$h] = count($head)+1;
		
			$head_rows[$h] = $row;
			$matrix[$l][$h] = $Cell($row);
			
			$gLeft($row, $gLeftRow[$l]);
			$gFoot($row, $gFootRow[$h]);
			$gLeftHead($row, $gLeftHeadRow);
			$gLeftFoot($row, $gLeftFootRow);
		}
		
		foreach($head_rows as $h=>$row) {
			$matrix[0][$h] = $Head($row);
		}
		
		$matrix[0][0] = $LeftHead($gLeftHeadRow);
		
		$end = count($left)+1;
		
		foreach($gLeftRow as $l=>$row) $matrix[$l][0] = $Left($row);
		foreach($gFootRow as $h=>$row) {
			$matrix[$end][$h] = $Foot($row);
		}

		$matrix[$end][0] = $LeftFoot($gLeftFootRow);

		$endj = count($head)+1;		# чтобы внутренние счётчики массивов совпадали с индексами
		for($i=0; $i<=$end; $i++) {
			for($j=0; $j<$endj; $j++) {
				$val = $matrix[$i][$j];
				$cells[$i][$j] = isset($val)? $val: "-";
			}
		}

		//foreach($cells as $x) mem(implode(", ", $x));
		//show();

		return $cells;
	}

	function chartData() {

		$slice = $this->columnSlice();
		$square = $this->content["square"];
		$chart_x = $square["chart_x"];
		$chart_y = $square["chart_y"];

		if(!trim($chart_x)) $chart_x = $slice[0][0];
		if(!trim($chart_y)) $chart_y = '$'.$slice[1][0];
		$chart_y = self::cell_tpl($chart_y);

		$rows = $this->data();
		$n = isset($_REQUEST["count"]) ? $_REQUEST["count"]+0: 30;
		if($n && count($rows) > $n) {
			$sort = create_function('$a, $b', "return \$b['$chart_x']-\$a['$chart_x'];");
			usort($rows, $sort);
			$other = array_slice($rows, $n);
			foreach($other as $row) $other_sum += $row[$chart_x];
			$other = 1;
			$rows = array_slice($rows, 0, $n);
		}

		foreach($rows as $k=>$row) {
			$data[] = array("label"=>$chart_y($row), "data"=>0+$row[$chart_x]);
		}

		if($other) $data[] = array("label"=>"Остальные", "data"=>$other_sum);

		return $data;
	}

	function flotData() {

		$column = $this->columnSet();
		$slice = $this->columnSlice();
		$square = $this->content["square"];
		$flot_x = $square["flot_x"];
		$flot_y = $square["flot_y"];

		if(!trim($flot_y)) $flot_y = $slice[0][0];
		if(!($flot_x = trim($flot_x))) {
			$flot_x = array();
			foreach($slice as $s) if($s[0]!=$flot_y) $flot_x[] = $s[0];
		} else {
			$flot_x = explode(" ", $flot_x);
		}

		$order = $this->order;
		$this->order = self::col_quote($flot_y);
		$real = $this->data();
		$this->order = $order;

		foreach($real as $row) {
			$y = $row[$flot_y];
			foreach($flot_x as $k=>$col) $data[$k]["data"][] = array($y, $row[$col]);
		}
		foreach($flot_x as $k=>$col) {
			$c = $column[$col];
			$data[$k]["label"] = $c[2]? $c[2]: $c[0];
		}

		return $data;
	}

}
