<?php



class SiteController extends Controller
{
	private $tables;

	public function filters()
	{
		return array(
			'accessControl',
		);
	}
	
	/**
	 * Declares class-based actions.
	 */
	public function actions()
	{
		return array(
			// captcha action renders the CAPTCHA image displayed on the contact page
			'captcha'=>array(
				'class'=>'CCaptchaAction',
				'backColor'=>0xFFFFFF,
			),
			// page action renders "static" pages stored under 'protected/views/site/pages'
			// They can be accessed via: index.php?r=site/page&view=FileName
			'page'=>array(
				'class'=>'CViewAction',
			),
		);
	}

	public function accessRules()
	{
		return array(
			array('allow',
				'actions'=>array('index','error', 'contact', 'login', 'logout'),
				'users'=>array('*'),
			),
			array('allow', // allow authenticated user to perform actions
				'actions'=>array('report', 'reportqbe', 'reportqbesave', 'reportqbeerase', 'qbeautofield', 'reportcopy'),
				'users'=>array('@'),
			),
			array('deny',  // deny all users
				'users'=>array('*'),
			),
		);
	}
	
	/**
	 * This is the default 'index' action that is invoked
	 * when an action is not explicitly requested by users.
	 */
	public function actionIndex()
	{
		// renders the view file 'protected/views/site/index.php'
		// using the default layout 'protected/views/layouts/main.php'
		$this->render('index');
	}

	public function actionQbeAutoField()
	{
		$id = $_REQUEST['id']+0;
		$col = $_REQUEST['col'];
		$term = $_REQUEST['term'];
		
		$model = Report::model()->findByPk($id);
		$qbe = new Qbe($model->content);
		
		$res = $qbe->autocomplete($col, $term);
		
		echo json_encode($res, JSON_NUMERIC_CHECK | JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);
	}
	
	public function actionReport()
	{
		$id = $_REQUEST['id']+0;
		
		if(!$id) {
			$sc = Yii::app()->db->createCommand()->select('id')->from('report')->limit(1)->queryScalar();
			if($sc) $this->redirect(array('site/report', 'id'=>$sc));
		}

		$reports = Yii::app()->db->createCommand()
			->select('id, name')
			->from('report')
			->queryAll();


		$menu = array();
		foreach($reports as $report) {
			$menu[] = array('label'=>$report["id"].' '.$report['name'], 'url'=>array('site/report', 'id'=>$report["id"]));
		}
		
		if(count($reports)==0) $name = "Ещё нет отчётов";
		else {
			array_unshift($menu,
				array('label'=>'Редактировать', 'url'=>array('site/reportqbe', 'id'=>$id)),
				array('label'=>'Удалить', 'url'=>array('site/reportqbeerase', 'id'=>$id)),
				array('label'=>'Создать на основе', 'url'=>array('site/reportcopy', 'id'=>$id)),
				array('label'=>''),
				array('label'=>''),
				array('label'=>'')
			);
		}

		array_unshift($menu, array('label'=>'Новый отчёт', 'url'=>array('site/reportqbe', 'id'=>-1)));

		$this->layout = '//layouts/column2';
		$this->menu = $menu;

		$model = Report::model()->findByPk($id);
		
		$qbe = new Qbe($model->content);		
		
		$qbe->set_filters($_REQUEST['Filter']);
		
		$this->render('report', array('model'=>$model, 'qbe'=>$qbe));
	}

	public function actionReportCopy()
	{
		$id = $_REQUEST['id']+0;
		$fields = "content, `sql`, for_users, explainas, author_id";
		Yii::app()->db->createCommand("INSERT INTO report ($fields, name) SELECT $fields, concat('Копия ', name) as name FROM report WHERE id=$id")->execute();
		$new_id = Yii::app()->db->createCommand("SELECT LAST_INSERT_ID()")->queryScalar();
		$this->redirect(Yii::app()->createUrl('site/reportqbe') ."&id=$new_id");
	}
	
	public function actionReportQbe()
	{	
		$id = $_REQUEST['id'];
		if(!$id) {
			$id = Yii::app()->db->createCommand('select id from report order by id limit 1')->queryScalar();
			if($id) $this->redirect( Yii::app()->createUrl('site/reportqbe') ."&id=". $id);
		}
		
		if(!$id or $id == -1) {
			$model = new Report();
			$model->name = 'Новый отчёт';
			$model->content = "{}";
			$model->sql = 'select 1';
			$model->explainas = '[]';
			$model->type = 'tab';
			$model->for_users = 0;
			$model->author_id = Yii::app()->user->id;
			$model->now = strftime("%Y-%m-%d %H:%M:%S", time());
			$model->save();
			$errors = $model->getErrors();
			if($errors) {
				print_r($errors);
				exit;
			}
			$this->redirect( Yii::app()->createUrl('site/reportqbe') ."&id=". $model->id);
		}

		$model = Report::model()->findByPk($id);

		$hide = array('report'=>1, 'tbl_admin'=>1);

		$tab = Yii::app()->db->createCommand()
			->select('table_name, column_name, column_key')
			->from('information_schema.columns')
			->where('TABLE_SCHEMA=:ts', array(':ts'=>Qbe::get_schema()))
			->queryAll();

		foreach($tab as $row) {
			$table = $row["table_name"];
			if(isset($hide[$table])) continue;

			if($table != $old_table) { $i = 0; $old_table = $table; $prefix = ""; }
			else if($i>8) { $i = 0; $prefix = "."; }
			$i++;
			//$dataProvider[$i][$prefix.$table] = $column;
		
			$tables[$prefix.$table][] = array($row["column_name"], strtolower($row["column_key"]));
		}
	
		foreach($tables as $table=>$columns) {
			$c = count($columns);
			if($c > $count) $count = $c;
		}
		
		$content = json_decode($model->content);
		
		$this->render('report_qbe', array('tables'=>$tables, 'count'=>$count, 'model'=>$model, 'content'=>$content));
	}
		
	public function actionReportQbeSave() {
		
		$id = $_REQUEST['id'];
		$name = $_REQUEST['name'];
		$for_users = $_REQUEST['for_users']+0;
		$type = $_REQUEST['type'];
		$content = $_REQUEST['content'];

		$qbe = new Qbe($content);

		if($_REQUEST['explain']) try {
			$explain = Yii::app()->db->createCommand('EXPLAIN '.$qbe->sql)->queryAll();
		} catch(Exception $e) {
			$explain = array('msg'=>$e->getMessage(), 'code'=>$e->getCode());
		}

		$model = Report::model()->findByPk($id);
		$model->editor_id = Yii::app()->user->id;
		$model->name = $name;
		$model->for_users = $for_users;
		$model->type = $type;
		$model->content = $content;
		$model->sql = $qbe->sql;
		$model->explainas = json_encode($explain);
		$model->save();
		$errors = $model->getErrors();

		echo json_encode($errors? array('errors'=>$errors): array('sql'=>$qbe->sql, 'explain'=>$explain));

	}

	public function actionReportQbeErase() {
		$id = $_REQUEST['id'];
		Yii::app()->db->createCommand()
			->delete("report", "id=:id", array(":id"=>$id));
		$this->redirect(array('site/report'));
	}


	/**
	 * This is the action to handle external exceptions.
	 */
	public function actionError()
	{
		if($error=Yii::app()->errorHandler->error)
		{
			if(Yii::app()->request->isAjaxRequest)
				echo $error['message'];
			else
				$this->render('error', $error);
		}
	}

	/**
	 * Displays the contact page
	 */
	public function actionContact()
	{
		$model=new ContactForm;
		if(isset($_POST['ContactForm']))
		{
			$model->attributes=$_POST['ContactForm'];
			if($model->validate())
			{
				$name='=?UTF-8?B?'.base64_encode($model->name).'?=';
				$subject='=?UTF-8?B?'.base64_encode($model->subject).'?=';
				$headers="From: $name <{$model->email}>\r\n".
					"Reply-To: {$model->email}\r\n".
					"MIME-Version: 1.0\r\n".
					"Content-type: text/plain; charset=UTF-8";

				mail(Yii::app()->params['adminEmail'],$subject,$model->body,$headers);
				Yii::app()->user->setFlash('contact','Thank you for contacting us. We will respond to you as soon as possible.');
				$this->refresh();
			}
		}
		$this->render('contact',array('model'=>$model));
	}

	/**
	 * Displays the login page
	 */
	public function actionLogin()
	{
		$model=new LoginForm;

		// if it is ajax validation request
		if(isset($_POST['ajax']) && $_POST['ajax']==='login-form')
		{
			echo CActiveForm::validate($model);
			Yii::app()->end();
		}

		// collect user input data
		if(isset($_POST['LoginForm']))
		{
			$model->attributes=$_POST['LoginForm'];
			// validate user input and redirect to the previous page if valid
			if($model->validate() && $model->login())
				$this->redirect(Yii::app()->user->returnUrl);
		}
		// display the login form
		$this->render('login',array('model'=>$model));
	}

	/**
	 * Logs out the current user and redirect to homepage.
	 */
	public function actionLogout()
	{
		Yii::app()->user->logout();
		$this->redirect(Yii::app()->homeUrl);
	}
}