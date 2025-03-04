<p>
У нас есть 3 сущности tag, label и timeline. Тут описано их структура в виде JSON
</p>

<h1>Тэги</h1>

<p>
Тэг которым и размечтается видео 
</p>
`{
		"id": "gjgj5jfkj3",
		"name": "Поперечный",
		"description":"описание",
		"color": "FF5733",
		"defaultTimeBefore": 3,
		"defaultTimeAfter": 4,
		"groupName": "Пасы",
		"collection": "от YouChip"
	}`

<p>
id – uuid, выдается автоматически

name – String, название тэга

description – String, описание может быть пустым

color – String, цвет в формате hex, может быть пустым, тогда выдается дефолтный(#808080) серый цвет

defaultTimeBefore – кол-во секунд до момента нажатия на кнопку разметки

defaultTimeAfter – кол-во секунд после момента нажатия на кнопку разметки

groupName – группа к которой относится тэг

collection – 
</p>
